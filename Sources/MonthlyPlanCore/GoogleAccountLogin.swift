import Foundation

/// A short-lived PKCE request for signing in to the app through Supabase Google Auth.
public struct GoogleAccountLogin: Sendable {
  public let state = UUID().uuidString
  public let verifier = UUID().uuidString + UUID().uuidString
  public let created = Date()

  public init() {}

  public var redirect: URL {
    var parts = URLComponents(string: "monthly-plan://auth/callback")!
    parts.queryItems = [.init(name: "state", value: state)]
    return parts.url!
  }

  public func authorizationURL(project: SupabaseConfiguration) -> URL {
    var parts = URLComponents(
      url: project.url.appendingPathComponent("auth/v1/authorize"),
      resolvingAgainstBaseURL: false)!
    parts.queryItems = [
      .init(name: "provider", value: "google"),
      .init(name: "redirect_to", value: redirect.absoluteString),
      .init(name: "code_challenge", value: EmailLogin.challenge(for: verifier)),
      .init(name: "code_challenge_method", value: "s256"),
    ]
    return parts.url!
  }

  public func authorizationCode(from url: URL) throws -> String {
    guard Date().timeIntervalSince(created) < 900,
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "monthly-plan", parts.host == "auth", parts.path == "/callback",
      parts.user == nil, parts.password == nil, parts.port == nil,
      parts.queryItems?.filter({ $0.name == "state" }).count == 1,
      parts.queryItems?.first(where: { $0.name == "state" })?.value == state
    else { throw PlanError.invalid("Google 로그인 응답이 이 Mac의 요청과 일치하지 않습니다. 다시 시도해 주세요.") }
    var fragment = URLComponents()
    fragment.percentEncodedQuery = parts.percentEncodedFragment
    if (parts.queryItems ?? []).contains(where: { $0.name == "error" })
      || (fragment.queryItems ?? []).contains(where: { $0.name == "error" }) {
      throw PlanError.invalid("Google 계정 로그인이 취소되었거나 허용되지 않았습니다. Supabase의 Google 로그인 설정을 확인해 주세요.")
    }
    guard parts.queryItems?.filter({ $0.name == "code" }).count == 1,
      let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
      !code.isEmpty, code.count < 2048 else {
      throw PlanError.invalid("Google 로그인 응답에 인증 코드가 없습니다.")
    }
    return code
  }
}
