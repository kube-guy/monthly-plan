import CryptoKit
import Foundation

public struct SupabaseConfiguration: Codable, Equatable, Sendable {
  public let url: URL
  public let publishableKey: String
  public init(url: String, publishableKey: String) throws {
    let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parts = URLComponents(string: text), parts.scheme == "https",
      let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
      parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
      let cleanURL = URL(string: "https://\(host)\(parts.port.map { ":\($0)" } ?? "")")
    else { throw PlanError.invalid("Supabase 프로젝트의 https 주소를 입력해 주세요.") }
    let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
    var isAnon = false
    let segments = key.split(separator: ".")
    if segments.count == 3 {
      var part = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
        of: "_", with: "/")
      part += String(repeating: "=", count: (4 - part.count % 4) % 4)
      if let bytes = Data(base64Encoded: part),
        let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
      {
        isAnon = json["role"] as? String == "anon"
      }
    }
    guard key.count < 4096, !key.contains(where: { $0.isWhitespace }),
      (key.hasPrefix("sb_publishable_") && key.count > 20) || isAnon
    else {
      throw PlanError.invalid("publishable 또는 anon 키만 사용할 수 있습니다. secret·service_role 키는 넣지 마세요.")
    }
    self.url = cleanURL
    self.publishableKey = key
  }
  public var projectKey: String {
    SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
public struct SupabaseUser: Codable, Sendable {
  public let id: UUID
  public let email: String?
}
public struct SupabaseSession: Codable, Sendable {
  public var accessToken: String
  public var refreshToken: String
  public var expiresAt: TimeInterval
  public var user: SupabaseUser
  public var needsRefresh: Bool { expiresAt < Date().timeIntervalSince1970 + 120 }
}
public enum SupabaseFailure: LocalizedError {
  case unauthorized
  case rejected(Int)
  case authentication(String)
  public var errorDescription: String? {
    switch self {
    case .authentication("otp_expired"):
      "로그인 링크가 만료되었거나 이미 사용되었습니다. 앱에서 새 로그인 메일을 요청하고, 이 Mac에서 가장 최근 메일의 링크를 열어 주세요."
    case .authentication("over_email_send_rate_limit"), .authentication("over_request_rate_limit"):
      "인증 메일 발송 한도에 도달했습니다. 잠시 기다렸다가 다시 요청해 주세요. Supabase의 이메일 발송 한도도 확인할 수 있습니다."
    case .authentication("email_address_not_authorized"):
      "현재 Supabase 기본 메일 서비스는 이 이메일로 발송할 수 없습니다. 프로젝트 소유자 이메일을 사용하거나 프로젝트에 SMTP를 연결해 주세요."
    case .authentication("email_provider_disabled"), .authentication("signup_disabled"):
      "Supabase에서 이메일 로그인 또는 신규 가입이 꺼져 있습니다. 프로젝트의 인증 설정을 확인해 주세요."
    case .authentication("email_not_confirmed"):
      "이메일 확인이 완료되지 않았습니다. 가장 최근 가입 확인 메일의 링크를 복사해 앱에 붙여 넣어 주세요."
    case .authentication:
      "이메일 인증을 완료하지 못했습니다. 가장 최근에 받은 로그인 메일을 사용해 주세요."
    case .unauthorized: "로그인이 만료되었습니다. 다시 로그인해 주세요. 아직 전송하지 못한 변경은 이 Mac에 남아 있습니다."
    case .rejected(400): "인증번호·입력값 또는 Supabase 설정을 확인해 주세요. 인증번호는 한 번만 사용할 수 있습니다."
    case .rejected(403): "Supabase 접근 권한을 확인해 주세요. 이메일 인증과 데이터베이스 정책 설정이 필요합니다."
    case .rejected(404): "Supabase 데이터베이스 설정이 필요합니다. 설치 안내의 SQL을 먼저 적용해 주세요."
    case .rejected(429): "요청이 많습니다. 잠시 후 다시 시도해 주세요."
    case .rejected: "Supabase 요청을 완료하지 못했습니다. 변경 내용은 이 Mac에 보관됩니다."
    }
  }
}
public struct SupabaseClient: Sendable {
  public let configuration: SupabaseConfiguration
  private let session: URLSession
  public init(configuration: SupabaseConfiguration, session: URLSession? = nil) {
    self.configuration = configuration
    let settings = URLSessionConfiguration.ephemeral
    settings.urlCache = nil
    settings.requestCachePolicy = .reloadIgnoringLocalCacheData
    settings.timeoutIntervalForRequest = 25
    self.session = session ?? URLSession(configuration: settings)
  }
  public func request(
    path: String, method: String = "GET", token: String? = nil,
    query: [URLQueryItem] = [], body: Data? = nil
  ) throws -> URLRequest {
    guard
      [
        "auth/v1/otp", "auth/v1/verify", "auth/v1/token", "auth/v1/logout",
        "rest/v1/monthly_plan_records", "rest/v1/rpc/monthly_plan_push",
      ].contains(path)
    else { throw PlanError.invalid("알 수 없는 Supabase 요청입니다.") }
    var components = URLComponents(
      url: configuration.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    if !query.isEmpty { components.queryItems = query }
    var request = URLRequest(url: components.url!)
    request.httpMethod = method
    request.httpBody = body
    request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    return request
  }
  public func sendCode(email: String, login: EmailLogin? = nil) async throws {
    guard email.contains("@"), email.count <= 254 else {
      throw PlanError.invalid("이메일 주소를 확인해 주세요.")
    }
    var body: [String: Any] = ["email": email, "create_user": true]
    var query: [URLQueryItem] = []
    if let login {
      guard login.email == email else { throw PlanError.invalid("로그인 이메일을 확인해 주세요.") }
      body["code_challenge"] = EmailLogin.challenge(for: login.verifier)
      body["code_challenge_method"] = "s256"
      query = [.init(name: "redirect_to", value: login.redirect.absoluteString)]
    }
    _ = try await send(
      request(
        path: "auth/v1/otp", method: "POST", query: query,
        body: JSONSerialization.data(withJSONObject: body)))
  }
  public func completeLogin(callback: URL, login: EmailLogin) async throws -> SupabaseSession {
    let code = try login.authorizationCode(from: callback)
    let response = try await send(
      request(
        path: "auth/v1/token", method: "POST",
        query: [.init(name: "grant_type", value: "pkce")],
        body: JSONSerialization.data(withJSONObject: [
          "auth_code": code, "code_verifier": login.verifier,
        ])))
    let result = try decodeSession(response)
    guard result.user.email?.caseInsensitiveCompare(login.email) == .orderedSame else {
      throw PlanError.invalid("요청한 이메일과 로그인 계정이 다릅니다.")
    }
    return result
  }
  public func verify(email: String, code: String) async throws -> SupabaseSession {
    let parameters = try verificationParameters(email: email, input: code)
    let response = try await send(
      request(
        path: "auth/v1/verify", method: "POST",
        body: JSONSerialization.data(withJSONObject: parameters)))
    let result = try decodeSession(response)
    guard result.user.email?.caseInsensitiveCompare(email) == .orderedSame else {
      throw PlanError.invalid("입력한 이메일과 로그인 링크의 계정이 다릅니다.")
    }
    return result
  }
  public func verificationParameters(email: String, input: String) throws -> [String: String] {
    if input.range(of: "^[0-9]{6,10}$", options: .regularExpression) != nil {
      return ["email": email, "token": input, "type": "email"]
    }
    guard input.count <= 12000, let link = URLComponents(string: input),
      link.scheme == "https", link.host == configuration.url.host,
      link.port == configuration.url.port,
      link.user == nil, link.password == nil, link.path == "/auth/v1/verify",
      let token = link.queryItems?.first(where: { $0.name == "token" || $0.name == "token_hash" })?
        .value,
      token.range(of: "^[A-Za-z0-9_-]{20,512}$", options: .regularExpression) != nil,
      let type = link.queryItems?.first(where: { $0.name == "type" })?.value,
      ["magiclink", "signup", "email"].contains(type)
    else {
      throw PlanError.invalid("이메일의 로그인 링크를 복사해 붙여 넣거나 숫자 인증번호를 입력해 주세요. 연결한 프로젝트의 링크만 사용할 수 있습니다.")
    }
    // Verify the token directly; never follow a user-supplied redirect destination.
    return ["token_hash": token, "type": type]
  }
  public func refresh(_ value: SupabaseSession) async throws -> SupabaseSession {
    let response = try await send(
      request(
        path: "auth/v1/token", method: "POST",
        query: [.init(name: "grant_type", value: "refresh_token")],
        body: JSONSerialization.data(withJSONObject: ["refresh_token": value.refreshToken])))
    let refreshed = try decodeSession(response)
    guard refreshed.user.id == value.user.id else { throw SupabaseFailure.unauthorized }
    return refreshed
  }
  public func logout(_ token: String) async throws {
    _ = try await send(
      request(
        path: "auth/v1/logout", method: "POST", token: token,
        query: [.init(name: "scope", value: "local")]))
  }
  public func push(_ mutation: SyncMutation, token: String) async throws -> SyncRecord {
    struct Parameters: Encodable {
      let p_id: String
      let p_base_revision: Int64
      let p_mutation_id: UUID
      let p_value: SyncValue?
      let p_deleted: Bool
      enum CodingKeys: CodingKey { case p_id, p_base_revision, p_mutation_id, p_value, p_deleted }
      func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_id, forKey: .p_id)
        try container.encode(p_base_revision, forKey: .p_base_revision)
        try container.encode(p_mutation_id, forKey: .p_mutation_id)
        try container.encode(p_deleted, forKey: .p_deleted)
        try container.encode(p_value, forKey: .p_value)
      }
    }
    let body = try JSONEncoder().encode(
      Parameters(
        p_id: mutation.id, p_base_revision: mutation.baseRevision,
        p_mutation_id: mutation.mutationID, p_value: mutation.value, p_deleted: mutation.deleted))
    let data = try await send(
      request(path: "rest/v1/rpc/monthly_plan_push", method: "POST", token: token, body: body))
    let remote = try JSONDecoder().decode(SyncRecord.self, from: data).validated()
    guard remote.id == mutation.id else { throw PlanError.invalid("다른 일정의 동기화 응답입니다.") }
    return remote
  }
  public func pullPage(token: String, after: String? = nil) async throws -> [SyncRecord] {
    var query: [URLQueryItem] = [
      .init(name: "select", value: "id,revision,mutation_id,value,deleted"),
      .init(name: "order", value: "id.asc"), .init(name: "limit", value: "1000"),
    ]
    if let after { query.append(.init(name: "id", value: "gt.\(after)")) }
    let data = try await send(
      request(path: "rest/v1/monthly_plan_records", token: token, query: query))
    return try JSONDecoder().decode([SyncRecord].self, from: data).map { try $0.validated() }
  }
  public func pullSummary(key: String, token: String) async throws -> SyncRecord? {
    guard key.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
      throw PlanError.invalid("장소 식별자가 올바르지 않습니다.")
    }
    let id = "summary:" + key
    let data = try await send(request(
      path: "rest/v1/monthly_plan_records", token: token,
      query: [
        .init(name: "select", value: "id,revision,mutation_id,value,deleted"),
        .init(name: "id", value: "eq.\(id)"),
        .init(name: "limit", value: "1"),
      ]))
    let records = try JSONDecoder().decode([SyncRecord].self, from: data)
    guard let record = records.first else { return nil }
    guard record.id == id else { throw PlanError.invalid("다른 장소의 요약을 받았습니다.") }
    return try record.validated()
  }
  private func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw SupabaseFailure.rejected(0) }
    guard (200..<300).contains(response.statusCode) else {
      if let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let code = (error["error_code"] ?? error["code"]) as? String,
        [
          "otp_expired", "over_email_send_rate_limit", "over_request_rate_limit",
          "email_address_not_authorized", "email_provider_disabled", "signup_disabled",
          "email_not_confirmed",
        ].contains(code)
      {
        throw SupabaseFailure.authentication(code)
      }
      if response.statusCode == 401 { throw SupabaseFailure.unauthorized }
      throw SupabaseFailure.rejected(response.statusCode)
    }
    return data
  }
  private func decodeSession(_ data: Data) throws -> SupabaseSession {
    struct Response: Decodable {
      let access_token: String
      let refresh_token: String
      let expires_in: Double
      let expires_at: Double?
      let user: SupabaseUser
    }
    let response = try JSONDecoder().decode(Response.self, from: data)
    guard !response.access_token.isEmpty, !response.refresh_token.isEmpty else {
      throw SupabaseFailure.unauthorized
    }
    return SupabaseSession(
      accessToken: response.access_token, refreshToken: response.refresh_token,
      expiresAt: response.expires_at ?? Date().timeIntervalSince1970 + response.expires_in,
      user: response.user)
  }
}
