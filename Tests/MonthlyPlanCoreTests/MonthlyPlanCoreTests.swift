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
  func testGoogleRequestScopesAndKeyHeaders() throws {
    let client = PlacesClient(key: "TEST_ONLY_NOT_A_REAL_KEY")
    let req = try client.searchRequest(place: "서울숲", address: "서울 성동구")
    XCTAssertEqual(req.url?.host, "places.googleapis.com")
    XCTAssertNil(req.url?.query)
    XCTAssertEqual(req.value(forHTTPHeaderField: "X-Goog-Api-Key"), "TEST_ONLY_NOT_A_REAL_KEY")
    XCTAssertEqual(req.httpMethod, "POST")
    XCTAssertTrue(req.value(forHTTPHeaderField: "X-Goog-FieldMask")!.contains("places.id"))
    let detail = try client.detailsRequest(id: "ChIJExample")
    XCTAssertTrue(detail.value(forHTTPHeaderField: "X-Goog-FieldMask")!.contains("parkingOptions"))
    XCTAssertThrowsError(try client.detailsRequest(id: "../wrong"))
  }
  func testGoogleParkingMissingIsUnknownAndReviewsDecode() throws {
    let empty = try JSONDecoder().decode(GooglePlace.self, from: Data(#"{"id":"example"}"#.utf8))
    XCTAssertTrue(empty.parkingLines.isEmpty)
    let text =
      #"{"id":"example","parkingOptions":{"freeParkingLot":true,"valetParking":false},"reviews":[{"name":"r1","rating":4,"text":{"text":"좋았어요","languageCode":"ko"},"authorAttribution":{"displayName":"예시 작성자","uri":"https://www.google.com/maps/contrib/example"},"googleMapsUri":"https://www.google.com/maps/reviews/example"}]}"#
    let place = try JSONDecoder().decode(GooglePlace.self, from: Data(text.utf8))
    XCTAssertEqual(place.parkingLines, ["무료 주차장: 제공", "발레파킹: 제공하지 않음"])
    XCTAssertEqual(place.reviews?.first?.authorAttribution?.displayName, "예시 작성자")
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
      ("SQLite atomic persistence", suite.testSQLiteRoundTripAtomicBatchAndDelete),
      ("external place linking", suite.testExternalPlaceMappingAndDeletion),
      ("legacy migration", suite.testLegacyJSONImportedOnceWithoutRemovingSource),
      ("duplicate and place validation", suite.testDuplicateIDsAndInvalidPlaceIDRejected),
      ("Naver search URL", suite.testNaverLinkEscapesUserText),
      ("Google request scopes", suite.testGoogleRequestScopesAndKeyHeaders),
      ("external content decoding", suite.testGoogleParkingMissingIsUnknownAndReviewsDecode),
      ("offline queue restart", suite.testOfflineQueueSurvivesRestart),
      ("two Mac create edit delete", suite.testTwoDeviceCreateEditDelete),
      ("conflict keeps both versions", suite.testConflictPreservesBothAndChooseRemote),
      ("local conflict resolution", suite.testConflictChooseLocalUsesNewRevision),
      ("edit during upload", suite.testEditingDuringUploadDoesNotLoseChanges),
      ("delete during upload", suite.testDeletingDuringUploadDoesNotResurrect),
      ("place mapping sync", suite.testExternalPlaceSyncAndUnlink),
      ("invalid remote response", suite.testInvalidRemoteDoesNotDamageLocal),
      ("Supabase configuration safety", suite.testSupabaseConfigurationAndHeaders),
      ("magic link validation", suite.testMagicLinkValidation),
    ]
    for (name, operation) in tests {
      try operation()
      print("PASS \(name)")
    }
    try await runTransportChecks()
    print("\(tests.count + 3) checks passed")
  }
}
