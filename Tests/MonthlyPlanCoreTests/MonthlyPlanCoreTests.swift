import Foundation
import MonthlyPlanCore

final class MonthlyPlanCoreTests {
  var cleanups: [() throws -> Void] = []
  func addTeardownBlock(_ block: @escaping () throws -> Void) { cleanups.append(block) }
  deinit { for block in cleanups { try? block() } }
  let reference = PlanDate.parse("2026-09-28")!
  func parse(_ text: String) throws -> ParsedPlan {
    try XCTUnwrap(NaturalParser.parse(text, reference: reference).first)
  }
  func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  func testRelativeDateAndPlace() throws {
    let p = try parse("내일 오후 3시 서울숲에서 산책")
    XCTAssertEqual(p.event.date, "2026-09-29")
    XCTAssertEqual(p.event.time, "15:00")
    XCTAssertEqual(p.event.place, "서울숲")
    XCTAssertEqual(p.event.title, "산책")
    XCTAssertTrue(p.warnings.isEmpty)
  }
  func testRangeInheritsAfternoon() throws {
    let p = try parse("10월 3일 오후 2시부터 4시까지 성수동 카페에서 친구 만나기")
    XCTAssertEqual(p.event.date, "2026-10-03")
    XCTAssertEqual(p.event.endTime, "16:00")
    XCTAssertEqual(p.event.place, "성수동 카페")
  }
  func testMondayBasedRelativeWeeks() throws {
    XCTAssertEqual(try parse("다음주 화요일 오전 10시 사무실에서 회의").event.date, "2026-10-06")
    XCTAssertEqual(try parse("이번주 일요일 오전 10시 집에서 식사").event.date, "2026-10-04")
    XCTAssertEqual(try parse("다다음주 월요일 오후 3시 집에서 식사").event.date, "2026-10-12")
  }
  func testHalfHoursAndClockNotation() throws {
    XCTAssertEqual(try parse("모레 저녁 7시 반 한남동에서 저녁").event.time, "19:30")
    XCTAssertEqual(try parse("오늘 09:30 사무실에서 회의").event.time, "09:30")
    XCTAssertEqual(try parse("오늘 정오 집에서 점심").event.time, "12:00")
  }
  func testLeapDates() {
    XCTAssertNotNil(PlanDate.parse("2028-02-29"))
    XCTAssertNil(PlanDate.parse("2026-02-29"))
    XCTAssertNil(PlanDate.parse("2026-04-31"))
    XCTAssertNil(PlanDate.parse("2101-01-01"))
  }
  func testMissingAndAmbiguousTime() throws {
    XCTAssertEqual(try parse("서울숲에서 산책").event.date, "")
    let withoutTime = try parse("내일 서울숲에서 산책")
    XCTAssertEqual(withoutTime.event.time, "09:00")
    XCTAssertTrue(withoutTime.warnings.contains("시간이 없어 오전 9시로 설정했어요."))
    XCTAssertNoThrow(try withoutTime.event.validated())
    XCTAssertEqual(try parse("내일 3시 서울숲에서 산책").event.time, "")
    XCTAssertEqual(try parse("2월 30일 오후 3시 산책").event.date, "")
    XCTAssertEqual(try parse("내일 밤 12시 집에서 영화").event.time, "")
  }
  func testBatchAndCategory() throws {
    let p = try NaturalParser.parse("내일 오후 3시 서울숲 산책\n10/3 오전 10시 사무실에서 회의", reference: reference)
    XCTAssertEqual(p.count, 2)
    XCTAssertEqual(p[0].event.place, "서울숲")
    XCTAssertEqual(p[1].event.category, .work)
  }
  func testYearRollover() throws {
    let p = try NaturalParser.parse("내일 오전 9시 집에서 아침", reference: PlanDate.parse("2026-12-31")!)
    XCTAssertEqual(p[0].event.date, "2027-01-01")
  }
  func testExplicitLabels() throws {
    let p = try parse("10월 3일 오후 2시 장소: 국립현대미술관 서울, 제목: 전시 보기")
    XCTAssertEqual(p.event.place, "국립현대미술관 서울")
    XCTAssertEqual(p.event.category, .culture)
  }
  func testBatchLimits() {
    XCTAssertThrowsError(
      try NaturalParser.parse(Array(repeating: "오늘 오후 3시 산책", count: 21).joined(separator: "\n")))
    XCTAssertThrowsError(try NaturalParser.parse(""))
  }
  func testValidationAndOvernight() throws {
    XCTAssertEqual(PlanEvent().time, "09:00")
    var p = PlanEvent(title: "약속", date: "2026-09-28", time: "23:00", endTime: "01:00")
    XCTAssertThrowsError(try p.validated())
    p.endTime = ""
    p.latitude = 37.5
    XCTAssertThrowsError(try p.validated())
    p.longitude = 127
    XCTAssertNoThrow(try p.validated())
    p.latitude = .nan
    XCTAssertThrowsError(try p.validated())
  }
  func testCalendarDisplayAndLegacyEventDecode() throws {
    let original = PlanEvent(title: "여행", date: "2026-09-28", time: "00:00", isAllDay: true)
    XCTAssertEqual(original.displayTime, "종일")
    let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","title":"회의","date":"2026-09-28","time":"09:00","endTime":"","place":"","address":"","category":"work","notes":"","latitude":null,"longitude":null}"#
    let decoded = try JSONDecoder().decode(PlanEvent.self, from: Data(legacy.utf8))
    XCTAssertEqual(decoded.displayTime, "09:00")
    XCTAssertEqual(decoded.isAllDay, nil)
  }
  func testGoogleCalendarOAuthAndEventBoundaries() throws {
    let attempt = try GoogleOAuthAttempt(
      clientID: "123456-example.apps.googleusercontent.com", port: 49152)
    let url = attempt.authorizationURL
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    XCTAssertEqual(url.host, "accounts.google.com")
    XCTAssertEqual(query.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
    XCTAssertTrue(query.first(where: { $0.name == "scope" })!.value!.contains("calendar.events.readonly"))
    XCTAssertTrue(query.first(where: { $0.name == "scope" })!.value!.contains("openid email"))
    XCTAssertTrue(!query.first(where: { $0.name == "scope" })!.value!.contains("/auth/calendar "))
    let valid = URL(string: attempt.redirect.absoluteString + "?code=abc123&state=" + attempt.state)!
    XCTAssertEqual(try attempt.code(from: valid), "abc123")
    XCTAssertThrowsError(try attempt.code(from: URL(string: valid.absoluteString.replacingOccurrences(of: attempt.state, with: "wrong"))!))
    XCTAssertThrowsError(try attempt.code(from: URL(string: valid.absoluteString.replacingOccurrences(of: "127.0.0.1", with: "example.com"))!))
    let month = PlanDate.parse("2026-10-01")!
    let timed = try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(#"{"id":"one","summary":"출장","start":{"dateTime":"2026-10-10T23:00:00+09:00"},"end":{"dateTime":"2026-10-11T02:00:00+09:00"}}"#.utf8))
    let pieces = timed.plans(calendarID: "personal@example.com", month: month)
    XCTAssertEqual(pieces.map(\.date), ["2026-10-10", "2026-10-11"])
    XCTAssertEqual(pieces.map(\.displayTime), ["23:00", "종일"])
    XCTAssertEqual(pieces.map(\.id), timed.plans(calendarID: "personal@example.com", month: month).map(\.id))
    let allDay = try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(#"{"id":"two","summary":"여행","start":{"date":"2026-10-01"},"end":{"date":"2026-10-03"}}"#.utf8))
    XCTAssertEqual(allDay.plans(calendarID: "personal@example.com", month: month).map(\.date), ["2026-10-01", "2026-10-02"])
  }
  func testGoogleAccountOAuthCallbackIsolation() throws {
    let config = try SupabaseConfiguration(url: "https://test.supabase.co",
      publishableKey: "sb_publishable_TEST_FIXTURE_ONLY")
    let login = GoogleAccountLogin()
    let authorize = login.authorizationURL(project: config)
    let query = URLComponents(url: authorize, resolvingAgainstBaseURL: false)!.queryItems!
    XCTAssertEqual(authorize.host, "test.supabase.co")
    XCTAssertEqual(authorize.path, "/auth/v1/authorize")
    XCTAssertEqual(query.first(where: { $0.name == "provider" })?.value, "google")
    XCTAssertEqual(query.first(where: { $0.name == "code_challenge_method" })?.value, "s256")
    XCTAssertEqual(query.first(where: { $0.name == "redirect_to" })?.value, login.redirect.absoluteString)
    let valid = URL(string: login.redirect.absoluteString + "&code=TEST_CODE")!
    XCTAssertEqual(try login.authorizationCode(from: valid), "TEST_CODE")
    XCTAssertThrowsError(try login.authorizationCode(from: URL(string:
      valid.absoluteString.replacingOccurrences(of: login.state, with: "other"))!))
    XCTAssertThrowsError(try login.authorizationCode(from: URL(string:
      valid.absoluteString.replacingOccurrences(of: "monthly-plan://auth", with: "monthly-plan://evil"))!))
  }
  func testSQLiteRoundTripAtomicBatchAndDelete() throws {
    let url = try directory().appendingPathComponent("plans.sqlite")
    let repo = try EventRepository(fileURL: url)
    let one = PlanEvent(title: "기록", date: "2026-09-28")
    try repo.save([one])
    XCTAssertEqual(try repo.load(), [one])
    var bad = one
    bad.title = ""
    let two = PlanEvent(title: "두 번째", date: "2026-09-29")
    XCTAssertThrowsError(try repo.save([two, bad]))
    XCTAssertEqual(try repo.load(), [one])
    let reopened = try EventRepository(fileURL: url)
    XCTAssertEqual(try reopened.load(), [one])
    try repo.delete(id: one.id)
    XCTAssertTrue(try repo.load().isEmpty)
  }
  func testExternalPlaceMappingAndDeletion() throws {
    let repo = try EventRepository(fileURL: try directory().appendingPathComponent("plans.sqlite"))
    let one = PlanEvent(title: "첫 방문", date: "2026-09-28", place: "카페", address: "서울 1")
    let two = PlanEvent(title: "재방문", date: "2026-10-03", place: "카페", address: "서울 1")
    try repo.save([one, two])
    try repo.linkExternalPlace(id: "ChIJTest_123", to: one)
    XCTAssertEqual(try repo.externalPlaceID(for: two), "ChIJTest_123")
    try repo.delete(id: one.id)
    XCTAssertEqual(try repo.externalPlaceID(for: two), "ChIJTest_123")
    var different = two
    different.address = "서울 2"
    XCTAssertNil(try repo.externalPlaceID(for: different))
    try repo.unlinkExternalPlace(for: two)
    XCTAssertNil(try repo.externalPlaceID(for: two))
  }
  func testLegacyJSONImportedOnceWithoutRemovingSource() throws {
    let dir = try directory()
    let legacy = dir.appendingPathComponent("events.json")
    let db = dir.appendingPathComponent("plans.sqlite")
    let e = PlanEvent(title: "이전 일정", date: "2026-09-28")
    let data = try JSONEncoder().encode([e])
    try data.write(to: legacy)
    let repo = try EventRepository(fileURL: db, legacyURL: legacy)
    XCTAssertEqual(try repo.load(), [e])
    try repo.delete(id: e.id)
    let again = try EventRepository(fileURL: db, legacyURL: legacy)
    XCTAssertTrue(try again.load().isEmpty)
    XCTAssertEqual(try Data(contentsOf: legacy), data)
  }
  func testDuplicateIDsAndInvalidPlaceIDRejected() throws {
    let repo = try EventRepository(fileURL: try directory().appendingPathComponent("plans.sqlite"))
    let e = PlanEvent(title: "약속", date: "2026-09-28", place: "서울숲")
    XCTAssertThrowsError(try repo.save([e, e]))
    XCTAssertThrowsError(try repo.linkExternalPlace(id: "../bad", to: e))
  }
  func testNaverLinkEscapesUserText() {
    let e = PlanEvent(place: "서울숲 & 카페")
    XCTAssertEqual(e.naverURL?.host, "map.naver.com")
    XCTAssertTrue(e.naverURL!.absoluteString.contains("%"))
  }
}

extension MonthlyPlanCoreTests {
  func testCodexPromptSharesOnlyPlaceAndAddress() throws {
    let prompt = try CodexPlaceClient.prompt(place: "서울숲", address: "서울 성동구")
    XCTAssertTrue(prompt.contains("장소명: 서울숲"))
    XCTAssertTrue(prompt.contains("주소: 서울 성동구"))
    XCTAssertTrue(prompt.contains("로컬 파일 읽기"))
    XCTAssertThrowsError(try CodexPlaceClient.prompt(place: " ", address: "서울"))
  }
  func testCodexSummaryRequiresSafeSources() throws {
    let data = Data(#"{"parking":"주차 정보 없음","reviews":"후기 없음","sources":[{"title":"출처","url":"https://example.com/place"},{"title":"위험","url":"javascript:alert(1)"}]}"#.utf8)
    let summary = try CodexPlaceClient.decode(data)
    XCTAssertEqual(summary.parking, "주차 정보 없음")
    XCTAssertEqual(summary.reviews, "후기 없음")
    XCTAssertEqual(summary.sources.count, 1)
    XCTAssertEqual(summary.sources.first?.url.host, "example.com")
    let noSources = Data(#"{"parking":"추측","reviews":"추측","sources":[]}"#.utf8)
    XCTAssertThrowsError(try CodexPlaceClient.decode(noSources))
  }
}

private func XCTAssertEqual<T: Equatable>(
  _ a: T, _ b: T, file: StaticString = #file, line: UInt = #line
) { precondition(a == b, "Expected \(b), got \(a)", file: file, line: line) }
private func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
  precondition(value, "Expected true", file: file, line: line)
}
private func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
  precondition(value == nil, "Expected nil", file: file, line: line)
}
private func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
  precondition(value != nil, "Expected value", file: file, line: line)
}
private func XCTUnwrap<T>(_ value: T?) throws -> T {
  guard let value else { throw PlanError.invalid("Unexpected nil") }
  return value
}
private func XCTAssertThrowsError<T>(
  _ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line
) {
  do {
    _ = try expression()
    preconditionFailure("Expected error", file: file, line: line)
  } catch {}
}
private func XCTAssertNoThrow<T>(
  _ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line
) {
  do { _ = try expression() } catch {
    preconditionFailure("Unexpected error: \(error)", file: file, line: line)
  }
}
@main enum RunChecks {
  static func main() async throws {
    let suite = MonthlyPlanCoreTests()
    let tests: [(String, () throws -> Void)] = [
      ("relative date and place", suite.testRelativeDateAndPlace),
      ("time range", suite.testRangeInheritsAfternoon),
      ("week boundaries", suite.testMondayBasedRelativeWeeks),
      ("clock formats", suite.testHalfHoursAndClockNotation),
      ("leap dates", suite.testLeapDates),
      ("ambiguous input", suite.testMissingAndAmbiguousTime),
      ("multiple schedules", suite.testBatchAndCategory),
      ("year rollover", suite.testYearRollover),
      ("explicit labels", suite.testExplicitLabels),
      ("input limits", suite.testBatchLimits),
      ("event validation", suite.testValidationAndOvernight),
      ("calendar display compatibility", suite.testCalendarDisplayAndLegacyEventDecode),
      ("Google OAuth and calendar boundaries", suite.testGoogleCalendarOAuthAndEventBoundaries),
      ("Google account OAuth callback isolation", suite.testGoogleAccountOAuthCallbackIsolation),
      ("SQLite atomic persistence", suite.testSQLiteRoundTripAtomicBatchAndDelete),
      ("external place linking", suite.testExternalPlaceMappingAndDeletion),
      ("legacy migration", suite.testLegacyJSONImportedOnceWithoutRemovingSource),
      ("duplicate and place validation", suite.testDuplicateIDsAndInvalidPlaceIDRejected),
      ("Naver search URL", suite.testNaverLinkEscapesUserText),
      ("Codex prompt data scope", suite.testCodexPromptSharesOnlyPlaceAndAddress),
      ("Codex source validation", suite.testCodexSummaryRequiresSafeSources),
      ("offline queue restart", suite.testOfflineQueueSurvivesRestart),
      ("two Mac create edit delete", suite.testTwoDeviceCreateEditDelete),
      ("conflict keeps both versions", suite.testConflictPreservesBothAndChooseRemote),
      ("local conflict resolution", suite.testConflictChooseLocalUsesNewRevision),
      ("edit during upload", suite.testEditingDuringUploadDoesNotLoseChanges),
      ("delete during upload", suite.testDeletingDuringUploadDoesNotResurrect),
      ("place mapping sync", suite.testExternalPlaceSyncAndUnlink),
      ("place summary persistence and sync", suite.testPlaceSummaryPersistsAndFirstCloudResultWins),
      ("invalid remote response", suite.testInvalidRemoteDoesNotDamageLocal),
      ("Supabase configuration safety", suite.testSupabaseConfigurationAndHeaders),
      ("magic link validation", suite.testMagicLinkValidation),
    ]
    for (name, operation) in tests {
      try operation()
      print("PASS \(name)")
    }
    try await runTransportChecks()
    print("\(tests.count + 8) checks passed")
  }
}
