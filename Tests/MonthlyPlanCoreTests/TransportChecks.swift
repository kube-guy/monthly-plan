import Foundation
import MonthlyPlanCore

private final class MockState: @unchecked Sendable {
  let lock = NSLock()
  var responses: [(Int, Data)] = []
  var requests: [URLRequest] = []
  func reset(_ values: [(Int, Data)]) {
    lock.lock()
    defer { lock.unlock() }
    responses = values
    requests = []
  }
  func next(_ request: URLRequest) -> (Int, Data) {
    lock.lock()
    defer { lock.unlock() }
    requests.append(request)
    precondition(!responses.isEmpty, "Unexpected network request")
    return responses.removeFirst()
  }
  func recorded() -> [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return requests
  }
}
private final class MockHTTP: URLProtocol, @unchecked Sendable {
  static let state = MockState()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let (status, data) = Self.state.next(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
private func testClient() throws -> SupabaseClient {
  let settings = URLSessionConfiguration.ephemeral
  settings.protocolClasses = [MockHTTP.self]
  return SupabaseClient(
    configuration: try SupabaseConfiguration(
      url: "https://test.supabase.co", publishableKey: "sb_publishable_TEST_FIXTURE_ONLY"),
    session: URLSession(configuration: settings))
}
private func body(_ request: URLRequest) throws -> [String: Any] {
  var data = request.httpBody ?? Data()
  if let stream = request.httpBodyStream {
    stream.open()
    defer { stream.close() }
    var bytes = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&bytes, maxLength: bytes.count)
      if count <= 0 { break }
      data.append(contentsOf: bytes.prefix(count))
    }
  }
  return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}
func runTransportChecks() async throws {
  let client = try testClient()
  let auth = Data(
    #"{"access_token":"TEST_ACCESS_ONLY","refresh_token":"TEST_REFRESH_ONLY","expires_in":3600,"user":{"id":"10000000-0000-0000-0000-000000000001","email":"example@example.invalid"}}"#
      .utf8)
  MockHTTP.state.reset([(200, Data("{}".utf8)), (200, auth), (200, auth)])
  try await client.sendCode(email: "example@example.invalid")
  let signedIn = try await client.verify(email: "example@example.invalid", code: "12345678")
  precondition(signedIn.user.id.uuidString == "10000000-0000-0000-0000-000000000001")
  _ = try await client.refresh(signedIn)
  let requests = MockHTTP.state.recorded()
  let otpBody = try body(requests[0])
  let verifyBody = try body(requests[1])
  precondition(otpBody["create_user"] as? Bool == true)
  precondition(verifyBody["type"] as? String == "email")
  precondition(requests[2].url?.query == "grant_type=refresh_token")
  print("PASS Supabase OTP and token refresh protocol")

  let deletion = SyncMutation(
    id: "20000000-0000-0000-0000-000000000001", baseRevision: 2, value: nil, deleted: true)
  let remote = SyncRecord(
    id: deletion.id, revision: 3, mutationID: deletion.mutationID, value: nil, deleted: true)
  MockHTTP.state.reset([
    (200, try JSONEncoder().encode(remote)), (200, try JSONEncoder().encode([remote])),
  ])
  _ = try await client.push(deletion, token: signedIn.accessToken)
  let page = try await client.pullPage(token: signedIn.accessToken, after: deletion.id)
  precondition(page == [remote])
  let syncRequests = MockHTTP.state.recorded()
  let params = try body(syncRequests[0])
  precondition(params["p_value"] is NSNull, "RPC deletion must include an explicit null parameter")
  precondition(params["p_base_revision"] as? Int == 2)
  precondition(syncRequests[1].url!.absoluteString.contains("id=gt."))
  print("PASS Supabase tombstone RPC and pagination protocol")

  MockHTTP.state.reset([(401, Data("{}".utf8))])
  do {
    _ = try await client.pullPage(token: "EXPIRED_TEST_TOKEN")
    preconditionFailure("401 must fail")
  } catch SupabaseFailure.unauthorized {}
  print("PASS Supabase expired session handling")
  let attempt = EmailLogin(email: "example@example.invalid")
  precondition(
    EmailLogin.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
      == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  let callback = URL(
    string: attempt.redirect.absoluteString + "&code=40000000-0000-0000-0000-000000000001")!
  MockHTTP.state.reset([(200, Data("{}".utf8)), (200, auth)])
  try await client.sendCode(email: attempt.email, login: attempt)
  _ = try await client.completeLogin(callback: callback, login: attempt)
  let pkce = MockHTTP.state.recorded()
  let sent = try body(pkce[0])
  let exchanged = try body(pkce[1])
  precondition(sent["code_challenge_method"] as? String == "s256")
  precondition(sent["code_challenge"] as? String == EmailLogin.challenge(for: attempt.verifier))
  precondition(exchanged["code_verifier"] as? String == attempt.verifier)
  precondition(pkce[0].url!.absoluteString.contains("redirect_to="))
  precondition(pkce[1].url!.query == "grant_type=pkce")
  print("PASS email callback PKCE challenge and exchange")
  let googleAccount = GoogleAccountLogin()
  let googleCallback = URL(string: googleAccount.redirect.absoluteString + "&code=TEST_GOOGLE_CODE")!
  MockHTTP.state.reset([(200, auth)])
  _ = try await client.completeGoogleLogin(callback: googleCallback, login: googleAccount)
  let accountRequests = MockHTTP.state.recorded()
  precondition(accountRequests.count == 1)
  precondition(accountRequests[0].url?.query == "grant_type=pkce")
  let accountExchange = try body(accountRequests[0])
  precondition(accountExchange["auth_code"] as? String == "TEST_GOOGLE_CODE")
  precondition(accountExchange["code_verifier"] as? String == googleAccount.verifier)
  print("PASS Google account callback PKCE exchange")
  for bad in [
    callback.absoluteString.replacingOccurrences(of: attempt.state, with: "different-state"),
    callback.absoluteString.replacingOccurrences(of: "monthly-plan:", with: "https:"),
    callback.absoluteString + "&state=" + attempt.state,
  ] {
    do {
      _ = try attempt.authorizationCode(from: URL(string: bad)!)
      preconditionFailure("Reject foreign login callback")
    } catch {}
  }
  print("PASS callback request binding")
  MockHTTP.state.reset([
    (403, Data(#"{"error_code":"otp_expired","msg":"Email link is invalid"}"#.utf8))
  ])
  do {
    _ = try await client.verify(email: "example@example.invalid", code: "12345678")
    preconditionFailure("Expired link must fail")
  } catch SupabaseFailure.authentication(let code) { precondition(code == "otp_expired") }
  print("PASS expired email error is distinct from database permissions")

  let googleSettings = URLSessionConfiguration.ephemeral
  googleSettings.protocolClasses = [MockHTTP.self]
  let google = GoogleCalendarAPI(session: URLSession(configuration: googleSettings))
  let googleAttempt = try GoogleOAuthAttempt(clientID: "123456-example.apps.googleusercontent.com", port: 49152)
  MockHTTP.state.reset([
    (200, Data(#"{"access_token":"GOOGLE_ACCESS","refresh_token":"GOOGLE_REFRESH","expires_in":3600}"#.utf8)),
    (200, Data(#"{"access_token":"GOOGLE_ACCESS_2","expires_in":3600}"#.utf8)),
    (200, Data(#"{"items":[{"id":"person@example.com","summary":"개인"}]}"#.utf8)),
    (200, Data(#"{"items":[{"id":"event-1","summary":"약속","start":{"date":"2026-10-03"},"end":{"date":"2026-10-04"}}]}"#.utf8)),
  ])
  let googleToken = try await google.exchange(code: "TEST_CODE", attempt: googleAttempt)
  let refreshedGoogleToken = try await google.refresh(googleToken)
  precondition(refreshedGoogleToken.refreshToken == "GOOGLE_REFRESH")
  let googleCalendars = try await google.calendars(token: refreshedGoogleToken.accessToken)
  let googleEvents = try await google.events(calendarID: googleCalendars[0].id,
    month: PlanDate.parse("2026-10-01")!, token: refreshedGoogleToken.accessToken)
  precondition(googleEvents.count == 1)
  let googleRequests = MockHTTP.state.recorded()
  precondition(googleRequests[0].url?.host == "oauth2.googleapis.com")
  precondition(googleRequests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
  precondition(googleRequests[2].url?.host == "www.googleapis.com")
  precondition(googleRequests[3].url?.path.contains("person@example.com") == true)
  precondition(googleRequests[3].value(forHTTPHeaderField: "Authorization") == "Bearer GOOGLE_ACCESS_2")
  print("PASS Google Calendar token refresh and read-only requests")

}
