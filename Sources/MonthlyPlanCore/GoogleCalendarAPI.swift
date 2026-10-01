import CryptoKit
import Foundation

public struct GoogleCalendarToken: Codable, Sendable {
  public let clientID: String
  public let accessToken: String
  public let refreshToken: String
  public let expiresAt: TimeInterval
  public var needsRefresh: Bool { expiresAt < Date().timeIntervalSince1970 + 120 }
}

public struct GoogleOAuthAttempt: Sendable {
  public let clientID: String
  public let state = UUID().uuidString + UUID().uuidString
  public let verifier = UUID().uuidString + UUID().uuidString
  public let created = Date()
  public let redirect: URL

  public init(clientID: String, port: UInt16) throws {
    let cleaned = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleaned.range(of: #"^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$"#,
      options: .regularExpression) != nil, port > 0 else {
      throw PlanError.invalid("Google Cloud의 데스크톱 앱 OAuth Client ID를 확인해 주세요.")
    }
    self.clientID = cleaned
    self.redirect = URL(string: "http://127.0.0.1:\(port)/oauth/callback")!
  }

  public var authorizationURL: URL {
    var parts = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    parts.queryItems = [
      .init(name: "client_id", value: clientID),
      .init(name: "redirect_uri", value: redirect.absoluteString),
      .init(name: "response_type", value: "code"),
      .init(name: "scope", value: "openid email https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.events.readonly"),
      .init(name: "access_type", value: "offline"),
      .init(name: "prompt", value: "consent"),
      .init(name: "state", value: state),
      .init(name: "code_challenge", value: EmailLogin.challenge(for: verifier)),
      .init(name: "code_challenge_method", value: "S256"),
    ]
    return parts.url!
  }

  public func code(from callback: URL) throws -> String {
    guard Date().timeIntervalSince(created) < 300,
      let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
      parts.scheme == "http", parts.host == "127.0.0.1", parts.port == redirect.port,
      parts.path == "/oauth/callback", parts.user == nil, parts.password == nil,
      parts.queryItems?.filter({ $0.name == "state" }).count == 1,
      parts.queryItems?.first(where: { $0.name == "state" })?.value == state else {
      throw PlanError.invalid("Google 로그인 응답이 이 Mac의 요청과 일치하지 않습니다. 다시 연결해 주세요.")
    }
    if parts.queryItems?.contains(where: { $0.name == "error" }) == true {
      throw PlanError.invalid("Google 캘린더 접근이 허용되지 않았습니다.")
    }
    guard parts.queryItems?.filter({ $0.name == "code" }).count == 1,
      let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
      !code.isEmpty, code.count < 2048 else {
      throw PlanError.invalid("Google 로그인 응답에 인증 코드가 없습니다.")
    }
    return code
  }
}

public struct GoogleCalendarItem: Decodable, Sendable, Identifiable {
  public let id: String
  public let summary: String
  public let backgroundColor: String?
  public let primary: Bool?
}

public struct GoogleAccountIdentity: Decodable, Sendable {
  public let sub: String
  public let email: String
  public let email_verified: Bool
}

public struct GoogleCalendarEvent: Decodable, Sendable {
  public struct When: Decodable, Sendable {
    public let date: String?
    public let dateTime: String?
  }
  public let id: String
  public let summary: String?
  public let description: String?
  public let location: String?
  public let status: String?
  public let start: When
  public let end: When

  public func plans(calendarID: String, month: Date) -> [PlanEvent] {
    guard status != "cancelled" else { return [] }
    let startDate = Self.parse(start)
    let endDate = Self.parse(end)
    guard let startDate, let endDate, endDate > startDate,
      let monthEnd = PlanDate.calendar.date(byAdding: .month, value: 1, to: PlanDate.first(month)) else { return [] }
    let monthStart = PlanDate.first(month)
    guard startDate < monthEnd, endDate > monthStart else { return [] }
    let firstDay = PlanDate.calendar.startOfDay(for: max(startDate, monthStart))
    let lastDay = PlanDate.calendar.startOfDay(for: min(endDate.addingTimeInterval(-0.001), monthEnd.addingTimeInterval(-0.001)))
    var day = firstDay
    var values: [PlanEvent] = []
    while day <= lastDay {
      let onFirstDay = PlanDate.calendar.isDate(day, inSameDayAs: startDate)
      let allDay = start.date != nil || !onFirstDay
      let date = PlanDate.string(day)
      let digest = SHA256.hash(data: Data("google|\(calendarID)|\(id)|\(date)".utf8))
      let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
      let uuid = UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))")!
      let startParts = PlanDate.calendar.dateComponents([.hour, .minute], from: startDate)
      let endParts = PlanDate.calendar.dateComponents([.hour, .minute], from: endDate)
      let time = allDay ? "00:00" : String(format: "%02d:%02d", startParts.hour!, startParts.minute!)
      let endTime = !allDay && PlanDate.calendar.isDate(startDate, inSameDayAs: endDate)
        ? String(format: "%02d:%02d", endParts.hour!, endParts.minute!) : ""
      values.append(PlanEvent(
        id: uuid, title: summary ?? "제목 없는 일정", date: date, time: time,
        endTime: endTime, place: location ?? "", notes: description ?? "", isAllDay: allDay))
      guard let next = PlanDate.calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    return values
  }

  private static func parse(_ when: When) -> Date? {
    if let date = when.date { return PlanDate.calendar.date(from: DateComponents(
      year: Int(date.prefix(4)) ?? 0, month: Int(date.dropFirst(5).prefix(2)) ?? 0,
      day: Int(date.suffix(2)) ?? 0)) }
    guard let value = when.dateTime else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = formatter.date(from: value) { return parsed }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}

public struct GoogleCalendarAPI: Sendable {
  private let session: URLSession
  public init(session: URLSession? = nil) {
    let settings = URLSessionConfiguration.ephemeral
    settings.timeoutIntervalForRequest = 25
    self.session = session ?? URLSession(configuration: settings)
  }

  public func exchange(code: String, attempt: GoogleOAuthAttempt) async throws -> GoogleCalendarToken {
    let data = try await tokenRequest([
      "client_id": attempt.clientID, "code": code, "code_verifier": attempt.verifier,
      "redirect_uri": attempt.redirect.absoluteString, "grant_type": "authorization_code",
    ])
    let reply = try JSONDecoder().decode(TokenReply.self, from: data)
    guard let refresh = reply.refresh_token, !refresh.isEmpty else {
      throw PlanError.invalid("Google이 재연결 토큰을 보내지 않았습니다. 다시 로그인해 주세요.")
    }
    return GoogleCalendarToken(clientID: attempt.clientID, accessToken: reply.access_token,
      refreshToken: refresh, expiresAt: Date().timeIntervalSince1970 + reply.expires_in)
  }

  public func refresh(_ token: GoogleCalendarToken) async throws -> GoogleCalendarToken {
    let data = try await tokenRequest([
      "client_id": token.clientID, "refresh_token": token.refreshToken,
      "grant_type": "refresh_token",
    ])
    let reply = try JSONDecoder().decode(TokenReply.self, from: data)
    return GoogleCalendarToken(clientID: token.clientID, accessToken: reply.access_token,
      refreshToken: reply.refresh_token ?? token.refreshToken,
      expiresAt: Date().timeIntervalSince1970 + reply.expires_in)
  }

  public func calendars(token: String) async throws -> [GoogleCalendarItem] {
    var items: [GoogleCalendarItem] = []
    var next: String?
    repeat {
      var parts = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
      parts.queryItems = [.init(name: "maxResults", value: "250")]
      if let next { parts.queryItems?.append(.init(name: "pageToken", value: next)) }
      let data = try await get(parts.url!, token: token)
      let page = try JSONDecoder().decode(CalendarPage.self, from: data)
      items += page.items ?? []
      next = page.nextPageToken
    } while next != nil && items.count < 1000
    return items
  }

  public func identity(token: String) async throws -> GoogleAccountIdentity {
    let data = try await get(URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!, token: token)
    let account = try JSONDecoder().decode(GoogleAccountIdentity.self, from: data)
    guard account.email_verified, !account.sub.isEmpty, account.sub.count < 256,
      account.email.contains("@"), account.email.count < 255 else {
      throw PlanError.invalid("Google 계정의 확인된 이메일을 읽지 못했습니다.")
    }
    return account
  }

  public func events(calendarID: String, month: Date, token: String) async throws -> [GoogleCalendarEvent] {
    guard let end = PlanDate.calendar.date(byAdding: .month, value: 1, to: PlanDate.first(month)) else { return [] }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    var items: [GoogleCalendarEvent] = []
    var next: String?
    repeat {
      let root = URL(string: "https://www.googleapis.com/calendar/v3/calendars")!
      var parts = URLComponents(url: root.appendingPathComponent(calendarID).appendingPathComponent("events"), resolvingAgainstBaseURL: false)!
      parts.queryItems = [
        .init(name: "singleEvents", value: "true"), .init(name: "maxResults", value: "2500"),
        .init(name: "timeMin", value: formatter.string(from: PlanDate.first(month))),
        .init(name: "timeMax", value: formatter.string(from: end)),
      ]
      if let next { parts.queryItems?.append(.init(name: "pageToken", value: next)) }
      let data = try await get(parts.url!, token: token)
      let page = try JSONDecoder().decode(EventPage.self, from: data)
      items += page.items ?? []
      next = page.nextPageToken
    } while next != nil && items.count < 10_000
    return items
  }

  private struct TokenReply: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double
  }
  private struct CalendarPage: Decodable {
    let items: [GoogleCalendarItem]?
    let nextPageToken: String?
  }
  private struct EventPage: Decodable {
    let items: [GoogleCalendarEvent]?
    let nextPageToken: String?
  }
  private func tokenRequest(_ fields: [String: String]) async throws -> Data {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var parts = URLComponents()
    parts.queryItems = fields.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
    request.httpBody = Data((parts.percentEncodedQuery ?? "").utf8)
    return try await send(request)
  }
  private func get(_ url: URL, token: String) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return try await send(request)
  }
  private func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
      throw PlanError.invalid("Google Calendar 연결에 실패했습니다. 계정 접근 권한과 API 설정을 확인해 주세요.")
    }
    return data
  }
}
