import CryptoKit
import Foundation

public struct EmailLogin: Sendable {
  public let email: String
  public let state = UUID().uuidString
  public let verifier = UUID().uuidString + UUID().uuidString
  public let created = Date()
  public init(email: String) { self.email = email }
  public static func challenge(for verifier: String) -> String {
    Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
  public var redirect: URL {
    var parts = URLComponents(string: "monthly-plan://auth/callback")!
    parts.queryItems = [.init(name: "state", value: state)]
    return parts.url!
  }
  public func authorizationCode(from url: URL) throws -> String {
    guard Date().timeIntervalSince(created) < 900,
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "monthly-plan", parts.host == "auth", parts.path == "/callback",
      parts.user == nil, parts.password == nil, parts.port == nil,
      parts.queryItems?.filter({ $0.name == "state" }).count == 1,
      parts.queryItems?.first(where: { $0.name == "state" })?.value == state
    else { throw PlanError.invalid("이 Mac에서 요청한 로그인과 일치하지 않습니다. 앱에서 새 로그인 메일을 요청해 주세요.") }
    var fragment = URLComponents()
    fragment.percentEncodedQuery = parts.percentEncodedFragment
    if (parts.queryItems ?? []).contains(where: { $0.name == "error" })
      || (fragment.queryItems ?? []).contains(where: { $0.name == "error" })
    {
      throw SupabaseFailure.authentication("otp_expired")
    }
    guard parts.queryItems?.filter({ $0.name == "code" }).count == 1,
      let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
      UUID(uuidString: code) != nil
    else { throw PlanError.invalid("로그인 응답에 인증 코드가 없습니다. Supabase의 앱 복귀 주소 설정을 확인해 주세요.") }
    return code
  }
}
