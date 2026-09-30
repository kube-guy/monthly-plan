import AppKit
import MonthlyPlanCore
import Security
import SwiftUI

@MainActor
final class DirectGoogleCalendarStore: ObservableObject {
  @Published private(set) var calendars: [GoogleCalendarItem] = []
  @Published private(set) var events: [PlanEvent] = []
  @Published private(set) var selectedIDs: Set<String>
  @Published private(set) var connected = false
  @Published private(set) var busy = false
  @Published private(set) var error: String?
  @Published private(set) var clientID: String?

  private let api = GoogleCalendarAPI()
  private let selectionKey = "monthly-plan.direct-google-calendar-selection"
  private var token: GoogleCalendarToken?
  private var month = PlanDate.first(Date())
  private var refreshTask: Task<Void, Never>?
  private var loopback: GoogleOAuthLoopback?

  init() {
    selectedIDs = Set(UserDefaults.standard.stringArray(forKey: selectionKey) ?? [])
    do {
      token = try GoogleCalendarCredentials.read()
      connected = token != nil
      clientID = token?.clientID
    } catch { self.error = error.localizedDescription }
  }

  func setMonth(_ value: Date) {
    month = PlanDate.first(value)
    refresh()
  }

  func toggle(_ id: String) {
    if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    UserDefaults.standard.set(selectedIDs.sorted(), forKey: selectionKey)
    refresh()
  }

  func connect(clientID: String) async {
    guard !busy else { return }
    busy = true
    error = nil
    do {
      let listener = try GoogleOAuthLoopback()
      loopback = listener
      let port = try await listener.start()
      let attempt = try GoogleOAuthAttempt(clientID: clientID, port: port)
      guard NSWorkspace.shared.open(attempt.authorizationURL) else {
        throw PlanError.invalid("기본 브라우저에서 Google 로그인 페이지를 열지 못했습니다.")
      }
      let callback = try await listener.waitForCallback()
      let code = try attempt.code(from: callback)
      let granted = try await api.exchange(code: code, attempt: attempt)
      try GoogleCalendarCredentials.save(granted)
      token = granted
      self.clientID = granted.clientID
      connected = true
      await load()
    } catch {
      self.error = error.localizedDescription
    }
    loopback?.stop()
    loopback = nil
    busy = false
  }

  func cancelConnection() {
    loopback?.stop()
    loopback = nil
    busy = false
  }

  func disconnect() {
    refreshTask?.cancel()
    loopback?.stop()
    do { try GoogleCalendarCredentials.remove() }
    catch { self.error = error.localizedDescription; return }
    token = nil
    connected = false
    clientID = nil
    selectedIDs = []
    UserDefaults.standard.removeObject(forKey: selectionKey)
    calendars = []
    events = []
    error = nil
  }

  func refresh() {
    refreshTask?.cancel()
    guard connected else { events = []; return }
    refreshTask = Task { await load() }
  }

  private func load() async {
    guard var token else { return }
    do {
      if token.needsRefresh {
        token = try await api.refresh(token)
        try Task.checkCancellation()
        try GoogleCalendarCredentials.save(token)
        self.token = token
      }
      let calendars = try await api.calendars(token: token.accessToken)
      try Task.checkCancellation()
      var values: [PlanEvent] = []
      for calendar in calendars where selectedIDs.contains(calendar.id) {
        let events = try await api.events(calendarID: calendar.id, month: month, token: token.accessToken)
        try Task.checkCancellation()
        values += events.flatMap { $0.plans(calendarID: calendar.id, month: month) }
      }
      self.calendars = calendars.sorted { ($0.primary == true ? 0 : 1, $0.summary) < ($1.primary == true ? 0 : 1, $1.summary) }
      self.events = PlanDate.sorted(values)
      error = nil
    } catch is CancellationError {
      // A newer month or selection has its own refresh.
    } catch {
      self.error = error.localizedDescription
    }
  }
}

private enum GoogleCalendarCredentials {
  private static var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "io.github.kube-guy.monthly-plan",
      kSecAttrAccount as String: "google-calendar-session",
    ]
  }

  static func read() throws -> GoogleCalendarToken? {
    var query = Self.query
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw PlanError.invalid("Google 로그인 정보를 키체인에서 읽지 못했습니다.")
    }
    return try JSONDecoder().decode(GoogleCalendarToken.self, from: data)
  }

  static func save(_ token: GoogleCalendarToken) throws {
    let data = try JSONEncoder().encode(token)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw PlanError.invalid("Google 로그인 정보를 키체인에 저장하지 못했습니다.")
      }
    } else if status != errSecSuccess {
      throw PlanError.invalid("Google 로그인 정보를 키체인에 저장하지 못했습니다.")
    }
  }

  static func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw PlanError.invalid("Google 로그인 정보를 키체인에서 삭제하지 못했습니다.")
    }
  }
}
