import AppKit
import Foundation
import MonthlyPlanCore
import SwiftUI

@MainActor
final class PlanStore: ObservableObject {
  @Published private(set) var events: [PlanEvent] = []
  @Published var error: String?
  @Published private(set) var configuration: SupabaseConfiguration?
  @Published private(set) var accountEmail: String?
  @Published private(set) var accountID = "local"
  @Published private(set) var syncStatus = "이 Mac에 저장 · 클라우드 연결 전"
  @Published private(set) var syncBusy = false
  @Published private(set) var authBusy = false
  @Published private(set) var conflicts: [SyncConflict] = []
  @Published private(set) var pendingCount = 0
  @Published private(set) var calendarSyncEnabled = false
  @Published private(set) var lastSync: Date?
  private var session: SupabaseSession?
  private var pendingLogin: EmailLogin?
  private var pendingGoogleLogin: GoogleAccountLogin?
  private var repository: EventRepository?
  private let directory: URL
  var signedIn: Bool { session != nil }
  var busy: Bool { syncBusy || authBusy }
  init() {
    let args = CommandLine.arguments
    if let index = args.firstIndex(of: "--data-dir"), args.count > index + 1 {
      directory = URL(fileURLWithPath: args[index + 1])
    } else {
      directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
        0
      ]
      .appendingPathComponent("monthly-plan")
    }
    do {
      if let data = UserDefaults.standard.data(forKey: "supabaseConfiguration") {
        let saved = try JSONDecoder().decode(SupabaseConfiguration.self, from: data)
        configuration = try SupabaseConfiguration(
          url: saved.url.absoluteString, publishableKey: saved.publishableKey)
        session = try CloudCredentials.read(saved.projectKey)
      }
      try openRepository()
    } catch {
      self.error = "저장소를 열지 못했습니다. 기존 파일은 보존됩니다. \(error.localizedDescription)"
    }
  }
  private func openRepository() throws {
    let nextID: String
    let target: URL
    if let configuration, let session {
      nextID = configuration.projectKey + "/" + session.user.id.uuidString
      target = directory.appendingPathComponent("accounts").appendingPathComponent(nextID)
    } else {
      nextID = "local"
      target = directory
    }
    let repo = try EventRepository(
      fileURL: target.appendingPathComponent("monthly-plan.sqlite"),
      legacyURL: nextID == "local" ? directory.appendingPathComponent("events.json") : nil)
    let loaded = try repo.load()
    repository = repo
    events = loaded
    accountID = nextID
    calendarSyncEnabled = signedIn && UserDefaults.standard.bool(
      forKey: "monthly-plan.calendar-sync." + nextID)
    accountEmail = session?.user.email
    conflicts = try repo.conflicts()
    pendingCount = try repo.pendingCount()
    lastSync = nil
    syncStatus = signedIn ? "동기화 대기" : "이 Mac에 저장 · 클라우드 연결 전"
    error = nil
  }
  private func ready() throws -> EventRepository {
    guard let repository else { throw PlanError.invalid("저장소를 읽을 수 없습니다. 기존 파일을 덮어쓰지 않습니다.") }
    return repository
  }
  private func reload() throws {
    let repo = try ready()
    events = try repo.load()
    conflicts = try repo.conflicts()
    pendingCount = try repo.pendingCount()
  }
  func save(_ values: [PlanEvent]) throws {
    try ready().save(values)
    try reload()
    scheduleSync()
  }
  func mirrorCalendarEvents(_ values: [PlanEvent]) {
    guard signedIn, calendarSyncEnabled else { return }
    do {
      let changed = try ready().mirrorCalendar(values)
      if changed > 0 {
        try reload()
        scheduleSync()
      }
    } catch { self.error = error.localizedDescription }
  }
  func setCalendarSyncEnabled(_ enabled: Bool) {
    guard signedIn else { return }
    UserDefaults.standard.set(enabled, forKey: "monthly-plan.calendar-sync." + accountID)
    calendarSyncEnabled = enabled
  }
  func delete(_ event: PlanEvent) throws {
    try ready().delete(id: event.id)
    try reload()
    scheduleSync()
  }
  func externalPlaceID(for event: PlanEvent) throws -> String? {
    try ready().externalPlaceID(for: event)
  }
  func linkExternalPlace(id: String, to event: PlanEvent) throws {
    try ready().linkExternalPlace(id: id, to: event)
    try reload()
    scheduleSync()
  }
  func unlinkExternalPlace(for event: PlanEvent) throws {
    try ready().unlinkExternalPlace(for: event)
    try reload()
    scheduleSync()
  }
  func cachedPlaceSummary(for event: PlanEvent) throws -> PlaceSummary? {
    try ready().summary(for: event)
  }
  func placeSummary(for event: PlanEvent) async throws -> PlaceSummary {
    let repo = try ready()
    let identity = accountID
    if let cached = try repo.summary(for: event) { return cached }
    if let configuration, var auth = session {
      let client = SupabaseClient(configuration: configuration)
      if auth.needsRefresh {
        auth = try await client.refresh(auth)
        guard accountID == identity, repository === repo else {
          throw PlanError.invalid("계정이 바뀌었습니다. 다시 열어 주세요.")
        }
        try CloudCredentials.save(auth, project: configuration.projectKey)
        session = auth
      }
      if let remote = try await client.pullSummary(key: event.placeKey, token: auth.accessToken) {
        guard accountID == identity, repository === repo else {
          throw PlanError.invalid("계정이 바뀌었습니다. 다시 열어 주세요.")
        }
        try repo.receive(remote)
        guard let cached = try repo.summary(for: event) else {
          throw PlanError.invalid("저장된 장소 요약을 읽지 못했습니다.")
        }
        return cached
      }
    }
    let result = try await CodexPlaceClient().summary(place: event.place, address: event.address)
    try Task.checkCancellation()
    guard accountID == identity, repository === repo else {
      throw PlanError.invalid("계정이 바뀌었습니다. 다시 열어 주세요.")
    }
    let saved = try repo.saveSummary(result, for: event)
    try reload()
    if signedIn { await sync() }
    return saved
  }
  private func scheduleSync() {
    if signedIn {
      syncStatus = "변경 \(pendingCount)개 전송 대기"
      Task { await sync() }
    }
  }
  func configure(url: String, key: String) throws {
    guard !busy, !signedIn else { throw PlanError.invalid("프로젝트를 바꾸려면 먼저 로그아웃해 주세요.") }
    let value = try SupabaseConfiguration(url: url, publishableKey: key)
    UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: "supabaseConfiguration")
    configuration = value
    pendingLogin = nil
    pendingGoogleLogin = nil
  }
  func sendCode(email: String) async throws {
    guard !busy, let configuration else { throw PlanError.invalid("프로젝트를 연결한 뒤 다시 시도해 주세요.") }
    authBusy = true
    defer { authBusy = false }
    let login = EmailLogin(email: email)
    try await SupabaseClient(configuration: configuration).sendCode(email: email, login: login)
    pendingLogin = login
    pendingGoogleLogin = nil
    error = nil
  }
  func startGoogleLogin() throws {
    guard !busy, !signedIn, let configuration else {
      throw PlanError.invalid("Supabase 프로젝트를 연결한 뒤 Google 로그인을 시도해 주세요.")
    }
    let login = GoogleAccountLogin()
    guard NSWorkspace.shared.open(login.authorizationURL(project: configuration)) else {
      throw PlanError.invalid("브라우저에서 Google 로그인 페이지를 열지 못했습니다.")
    }
    pendingGoogleLogin = login
    pendingLogin = nil
    error = nil
  }
  func login(email: String, code: String) async throws {
    guard !busy, let configuration else { throw PlanError.invalid("프로젝트를 연결한 뒤 다시 시도해 주세요.") }
    authBusy = true
    do {
      let value = try await SupabaseClient(configuration: configuration).verify(
        email: email, code: code)
      try CloudCredentials.save(value, project: configuration.projectKey)
      pendingLogin = nil
      // Clear the previous view before switching accounts, including on disk errors.
      session = value
      repository = nil
      events = []
      conflicts = []
      accountEmail = nil
      try openRepository()
      authBusy = false
      await sync()
    } catch {
      authBusy = false
      throw error
    }
  }
  func handleLoginCallback(_ url: URL) async {
    guard !busy, let configuration else {
      error = "이 Mac의 앱에서 새 로그인 메일을 요청한 뒤 링크를 열어 주세요."
      return
    }
    authBusy = true
    do {
      let value: SupabaseSession
      if let pendingGoogleLogin {
        value = try await SupabaseClient(configuration: configuration).completeGoogleLogin(
          callback: url, login: pendingGoogleLogin)
      } else if let pendingLogin {
        value = try await SupabaseClient(configuration: configuration).completeLogin(
          callback: url, login: pendingLogin)
      } else {
        throw PlanError.invalid("이 Mac의 앱에서 로그인을 시작한 뒤 다시 시도해 주세요.")
      }
      try CloudCredentials.save(value, project: configuration.projectKey)
      self.pendingLogin = nil
      self.pendingGoogleLogin = nil
      session = value
      repository = nil
      events = []
      conflicts = []
      accountEmail = nil
      try openRepository()
      authBusy = false
      await sync()
    } catch {
      authBusy = false
      self.error = error.localizedDescription
    }
  }
  func logout() async throws {
    guard !busy else { throw PlanError.invalid("현재 동기화가 끝난 뒤 다시 시도해 주세요.") }
    authBusy = true
    defer { authBusy = false }
    if let configuration, let session {
      try CloudCredentials.remove(configuration.projectKey)
      // Local logout works offline. Cached account data stays in its own directory.
      try? await SupabaseClient(configuration: configuration).logout(session.accessToken)
    }
    session = nil
    pendingLogin = nil
    pendingGoogleLogin = nil
    repository = nil
    events = []
    conflicts = []
    accountEmail = nil
    try openRepository()
  }
  func importLocalEvents() throws {
    guard signedIn, !busy else { throw PlanError.invalid("로그인하고 동기화가 끝난 뒤 가져올 수 있습니다.") }
    let local = try EventRepository(
      fileURL: directory.appendingPathComponent("monthly-plan.sqlite"),
      legacyURL: directory.appendingPathComponent("events.json"))
    // Fresh IDs avoid overwriting an existing remote event or resurrecting a tombstone.
    let originals = try local.load()
    guard !originals.isEmpty else { throw PlanError.invalid("이 Mac에 가져올 기존 일정이 없습니다.") }
    let copies = originals.map { event in
      var copy = event
      copy.id = UUID()
      return copy
    }
    try save(copies)
    for event in originals {
      if let summary = try local.summary(for: event) {
        try ready().saveSummary(summary, for: event)
      }
    }
    try reload()
    scheduleSync()
  }
  func resolve(_ conflict: SyncConflict, keepLocal: Bool) throws {
    guard !busy else { throw PlanError.invalid("동기화가 끝난 뒤 선택해 주세요.") }
    try ready().resolve(id: conflict.id, keepLocal: keepLocal)
    try reload()
    scheduleSync()
  }
  func sync() async {
    guard !busy, let configuration, var auth = session, let repo = repository else { return }
    syncBusy = true
    syncStatus = "동기화 중…"
    defer {
      syncBusy = false
      do { try reload() } catch { self.error = error.localizedDescription }
    }
    do {
      let client = SupabaseClient(configuration: configuration)
      if auth.needsRefresh {
        auth = try await client.refresh(auth)
        try CloudCredentials.save(auth, project: configuration.projectKey)
        session = auth
      }
      // Two passes pick up an edit made while the previous request was in flight.
      for _ in 0..<2 {
        for change in try repo.pending() {
          try Task.checkCancellation()
          let remote = try await client.push(change, token: auth.accessToken)
          try repo.receive(remote, sent: change)
        }
      }
      var after: String?
      while true {
        try Task.checkCancellation()
        let page = try await client.pullPage(token: auth.accessToken, after: after)
        for record in page { try repo.receive(record) }
        guard page.count == 1000, let last = page.last else { break }
        after = last.id
      }
      try reload()
      lastSync = Date()
      syncStatus =
        !conflicts.isEmpty
        ? "충돌 \(conflicts.count)개 · 내용 선택 필요"
        : pendingCount > 0 ? "변경 \(pendingCount)개 전송 대기" : "Supabase 동기화 완료"
    } catch is CancellationError { syncStatus = "동기화 대기" } catch {
      syncStatus = "동기화 대기 · \(error.localizedDescription)"
    }
  }
}
