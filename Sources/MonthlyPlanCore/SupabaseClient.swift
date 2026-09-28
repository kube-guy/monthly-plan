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
  public var errorDescription: String? {
    switch self {
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
  public func sendCode(email: String) async throws {
    guard email.contains("@"), email.count <= 254 else {
      throw PlanError.invalid("이메일 주소를 확인해 주세요.")
    }
    _ = try await send(
      request(
        path: "auth/v1/otp", method: "POST",
        body: JSONSerialization.data(withJSONObject: ["email": email, "create_user": true])))
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
  private func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw SupabaseFailure.rejected(0) }
    guard (200..<300).contains(response.statusCode) else {
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
