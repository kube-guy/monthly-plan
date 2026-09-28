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
}
