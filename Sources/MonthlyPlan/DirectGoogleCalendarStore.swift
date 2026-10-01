import AppKit
import MonthlyPlanCore
import Security
import SwiftUI

struct GoogleCalendarAccountInfo: Identifiable {
  let id: String
  let email: String
}

@MainActor
final class DirectGoogleCalendarStore: ObservableObject {
  @Published private(set) var accounts: [GoogleCalendarAccountInfo] = []
  @Published private(set) var calendarsByAccount: [String: [GoogleCalendarItem]] = [:]
  @Published private(set) var events: [PlanEvent] = []
  @Published private(set) var selectedIDsByAccount: [String: Set<String>] = [:]
  @Published private(set) var busy = false
  @Published private(set) var loading = false
  @Published private(set) var error: String?
  @Published private(set) var clientID: String?

  private let api = GoogleCalendarAPI()
  private let selectionKey = "monthly-plan.direct-google-calendar-selection"
  private let clientIDKey = "monthly-plan.direct-google-client-id"
  private var credentials: [StoredGoogleCalendarAccount] = []
  private var month = PlanDate.first(Date())
  private var refreshTask: Task<Void, Never>?
  private var loadID = UUID()
  private var activeConnectionID: UUID?
  private var loopback: GoogleOAuthLoopback?

  var connected: Bool { !accounts.isEmpty }

  init() {
    do {
      credentials = try GoogleCalendarCredentials.read()
      accounts = credentials.map { GoogleCalendarAccountInfo(id: $0.id, email: $0.email) }
      for account in credentials {
        selectedIDsByAccount[account.id] = Set(UserDefaults.standard.stringArray(
          forKey: selectionKeyForAccount(account.id)) ?? [])
      }
      clientID = UserDefaults.standard.string(forKey: clientIDKey) ?? credentials.last?.token.clientID
    } catch { self.error = error.localizedDescription }
  }

  func setMonth(_ value: Date) {
    month = PlanDate.first(value)
    refresh()
  }

  func isSelected(accountID: String, calendarID: String) -> Bool {
    selectedIDsByAccount[accountID]?.contains(calendarID) == true
  }

  func toggle(accountID: String, calendarID: String) {
    guard accounts.contains(where: { $0.id == accountID }) else { return }
    var selected = selectedIDsByAccount[accountID] ?? []
    if selected.contains(calendarID) { selected.remove(calendarID) }
    else { selected.insert(calendarID) }
    selectedIDsByAccount[accountID] = selected
    UserDefaults.standard.set(selected.sorted(), forKey: selectionKeyForAccount(accountID))
    refresh()
  }

  func connect(clientID: String) async {
    guard !busy else { return }
    let connectionID = UUID()
    activeConnectionID = connectionID
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
      let granted = try await api.exchange(code: attempt.code(from: callback), attempt: attempt)
      let identity = try await api.identity(token: granted.accessToken)
      let calendars = try await api.calendars(token: granted.accessToken)
      guard activeConnectionID == connectionID else { return }

      let item = StoredGoogleCalendarAccount(id: identity.sub, email: identity.email, token: granted)
      var updated = credentials.filter { $0.id != item.id }
      updated.append(item)
      try GoogleCalendarCredentials.save(updated)
      credentials = updated
      accounts = updated.map { GoogleCalendarAccountInfo(id: $0.id, email: $0.email) }
      calendarsByAccount[item.id] = calendars
      if selectedIDsByAccount[item.id] == nil {
        let initial = calendars.first(where: { $0.primary == true }) ?? calendars.first
        let selected = Set(initial.map { [$0.id] } ?? [])
        selectedIDsByAccount[item.id] = selected
        UserDefaults.standard.set(selected.sorted(), forKey: selectionKeyForAccount(item.id))
      }
      self.clientID = granted.clientID
      UserDefaults.standard.set(granted.clientID, forKey: clientIDKey)
      refresh()
    } catch {
      if activeConnectionID == connectionID { self.error = error.localizedDescription }
    }
    if activeConnectionID == connectionID {
      loopback?.stop()
      loopback = nil
      activeConnectionID = nil
      busy = false
    }
  }

  func cancelConnection() {
    activeConnectionID = nil
    loopback?.stop()
    loopback = nil
    busy = false
  }

  func disconnect(accountID: String) {
    guard let index = credentials.firstIndex(where: { $0.id == accountID }) else { return }
    var updated = credentials
    updated.remove(at: index)
    do { try GoogleCalendarCredentials.save(updated) }
    catch { self.error = error.localizedDescription; return }
    credentials = updated
    accounts = updated.map { GoogleCalendarAccountInfo(id: $0.id, email: $0.email) }
    selectedIDsByAccount.removeValue(forKey: accountID)
    calendarsByAccount.removeValue(forKey: accountID)
    UserDefaults.standard.removeObject(forKey: selectionKeyForAccount(accountID))
    error = nil
    refresh()
  }

  func refresh() {
    refreshTask?.cancel()
    loadID = UUID()
    guard connected else {
      events = []
      loading = false
      return
    }
    let id = loadID
    loading = true
    refreshTask = Task { await load(id: id) }
  }

  private func load(id: UUID) async {
    let snapshot = credentials
    let targetMonth = month
    var updated = snapshot
    var lists: [String: [GoogleCalendarItem]] = [:]
    var values: [PlanEvent] = []
    var failures: [String] = []
    for index in updated.indices {
      let account = updated[index]
      do {
        var token = account.token
        if token.needsRefresh { token = try await api.refresh(token) }
        let calendars = try await api.calendars(token: token.accessToken)
        try Task.checkCancellation()
        lists[account.id] = calendars.sorted {
          ($0.primary == true ? 0 : 1, $0.summary) < ($1.primary == true ? 0 : 1, $1.summary)
        }
        for calendar in calendars where isSelected(accountID: account.id, calendarID: calendar.id) {
          let events = try await api.events(calendarID: calendar.id, month: targetMonth,
            token: token.accessToken)
          try Task.checkCancellation()
          values += events.flatMap { $0.plans(calendarID: calendar.id,
            month: targetMonth) }
        }
        updated[index].token = token
      } catch is CancellationError { return }
      catch { failures.append("\(account.email): \(error.localizedDescription)") }
    }
    guard !Task.isCancelled, loadID == id else { return }
    do { try GoogleCalendarCredentials.save(updated); credentials = updated }
    catch { failures.append(error.localizedDescription) }
    calendarsByAccount = lists
    var seen = Set<UUID>()
    events = PlanDate.sorted(values.filter { seen.insert($0.id).inserted })
    error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    loading = false
  }

  private func selectionKeyForAccount(_ id: String) -> String {
    id == "legacy" ? selectionKey : selectionKey + "." + id
  }
}

private struct StoredGoogleCalendarAccount: Codable {
  let id: String
  let email: String
  var token: GoogleCalendarToken
}

private enum GoogleCalendarCredentials {
  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "io.github.kube-guy.monthly-plan",
      kSecAttrAccount as String: "google-calendar-session"]
  }

  static func read() throws -> [StoredGoogleCalendarAccount] {
    var query = Self.query
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess, let data = result as? Data else {
      throw PlanError.invalid("Google 로그인 정보를 키체인에서 읽지 못했습니다.")
    }
    if let accounts = try? JSONDecoder().decode([StoredGoogleCalendarAccount].self, from: data) {
      return accounts
    }
    let old = try JSONDecoder().decode(GoogleCalendarToken.self, from: data)
    return [StoredGoogleCalendarAccount(id: "legacy", email: "기존 Google 연결", token: old)]
  }

  static func save(_ accounts: [StoredGoogleCalendarAccount]) throws {
    if accounts.isEmpty {
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw PlanError.invalid("Google 로그인 정보를 키체인에서 삭제하지 못했습니다.")
      }
      return
    }
    let data = try JSONEncoder().encode(accounts)
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
}
