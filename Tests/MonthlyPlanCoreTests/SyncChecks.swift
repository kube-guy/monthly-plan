import Foundation
import MonthlyPlanCore

extension MonthlyPlanCoreTests {
  private func expect(_ ok: Bool, _ message: String) { precondition(ok, message) }
  private func repo() throws -> EventRepository {
    try EventRepository(fileURL: directory().appendingPathComponent("sync.sqlite"))
  }
  private func accepted(_ change: SyncMutation, revision: Int64? = nil) -> SyncRecord {
    SyncRecord(
      id: change.id, revision: revision ?? change.baseRevision + 1,
      mutationID: change.mutationID, value: change.value, deleted: change.deleted)
  }
  func testOfflineQueueSurvivesRestart() throws {
    let a = try repo()
    let e = PlanEvent(title: "오프라인 약속", date: "2026-09-28")
    try a.save([e])
    let pending = try a.pending()
    let reopened = try EventRepository(fileURL: a.fileURL)
    expect(try reopened.pending() == pending, "Outbox must survive restart")
    try reopened.receive(accepted(pending[0]), sent: pending[0])
    expect(try reopened.pendingCount() == 0, "Acknowledged mutation clears outbox")
    expect(try reopened.load() == [e], "Roundtrip must preserve event")
  }
  func testTwoDeviceCreateEditDelete() throws {
    let a = try repo()
    let b = try repo()
    var e = PlanEvent(title: "두 Mac", date: "2026-09-28")
    try a.save([e])
    let create = try a.pending()[0]
    let one = accepted(create)
    try a.receive(one, sent: create)
    try b.receive(one)
    expect(try b.load() == [e], "Other Mac sees create")
    e.title = "다른 Mac에서 수정"
    try b.save([e])
    let edit = try b.pending()[0]
    expect(edit.baseRevision == 1, "Edit uses server revision")
    let two = accepted(edit)
    try b.receive(two, sent: edit)
    try a.receive(two)
    expect(try a.load() == [e], "Original Mac sees edit")
    try a.delete(id: e.id)
    let deletion = try a.pending()[0]
    let three = accepted(deletion)
    try a.receive(three, sent: deletion)
    try b.receive(three)
    expect(try b.load().isEmpty, "Tombstone removes remote event")
    try b.receive(one)
    expect(try b.load().isEmpty, "Old response must not resurrect delete")
  }
  func testConflictPreservesBothAndChooseRemote() throws {
    let a = try repo()
    let b = try repo()
    var e = PlanEvent(title: "원본", date: "2026-09-28")
    try a.save([e])
    let seed = try a.pending()[0]
    let initial = accepted(seed)
    try a.receive(initial, sent: seed)
    try b.receive(initial)
    e.title = "맥 A"
    try a.save([e])
    let editA = try a.pending()[0]
    e.title = "맥 B"
    try b.save([e])
    let remote = accepted(editA)
    try b.receive(remote)
    expect(try b.conflicts().count == 1, "Concurrent change must surface conflict")
    expect(try b.load()[0].title == "맥 B", "Local edit remains until user chooses")
    expect(try b.pending().isEmpty, "Conflicts must not retry automatically")
    try b.resolve(id: e.id.uuidString, keepLocal: false)
    expect(try b.load()[0].title == "맥 A", "Remote choice installs remote")
    expect(try b.pendingCount() == 0, "Resolved remote clears outbox")
  }
  func testConflictChooseLocalUsesNewRevision() throws {
    let a = try repo()
    var e = PlanEvent(title: "내 수정", date: "2026-09-28")
    try a.save([e])
    let local = try a.pending()[0]
    e.title = "온라인 수정"
    let remote = SyncRecord(
      id: e.id.uuidString, revision: 4, mutationID: UUID(), value: SyncValue(event: e))
    try a.receive(remote)
    try a.resolve(id: e.id.uuidString, keepLocal: true)
    let retry = try a.pending()[0]
    expect(
      retry.baseRevision == 4 && retry.mutationID != local.mutationID,
      "Explicit local choice is a new CAS write")
    expect(retry.value?.event?.title == "내 수정", "Keep local contents")
  }
  func testEditingDuringUploadDoesNotLoseChanges() throws {
    let a = try repo()
    var e = PlanEvent(title: "업로드 중", date: "2026-09-28")
    try a.save([e])
    let sent = try a.pending()[0]
    e.title = "다시 수정"
    try a.save([e])
    try a.receive(accepted(sent), sent: sent)
    let next = try a.pending()[0]
    expect(
      next.value?.event?.title == e.title && next.baseRevision == 1,
      "New edit must be rebased, not cleared")
    expect(try a.load()[0].title == e.title, "New edit remains visible")
    try a.receive(accepted(next), sent: next)
    expect(try a.pendingCount() == 0, "Second upload acknowledges new edit")
  }
  func testDeletingDuringUploadDoesNotResurrect() throws {
    let a = try repo()
    let e = PlanEvent(title: "삭제 예정", date: "2026-09-28")
    try a.save([e])
    let sent = try a.pending()[0]
    try a.delete(id: e.id)
    try a.receive(accepted(sent), sent: sent)
    let next = try a.pending()[0]
    expect(next.deleted && next.baseRevision == 1, "Delete is retained during upload")
    expect(try a.load().isEmpty, "UI must not resurrect event")
  }
  func testExternalPlaceSyncAndUnlink() throws {
    let a = try repo()
    let b = try repo()
    let e = PlanEvent(title: "방문", date: "2026-09-28", place: "서울숲")
    try a.linkExternalPlace(id: "ChIJ_Example", to: e)
    let change = try a.pending()[0]
    let remote = accepted(change)
    try a.receive(remote, sent: change)
    try b.receive(remote)
    expect(try b.externalPlaceID(for: e) == "ChIJ_Example", "Other Mac shares place ID only")
    try b.unlinkExternalPlace(for: e)
    let unlink = try b.pending()[0]
    try a.receive(accepted(unlink))
    expect(try a.externalPlaceID(for: e) == nil, "Unlink syncs")
  }
  func testInvalidRemoteDoesNotDamageLocal() throws {
    let a = try repo()
    let e = PlanEvent(title: "안전한 원본", date: "2026-09-28")
    try a.save([e])
    let invalid = SyncRecord(
      id: UUID().uuidString, revision: 2, mutationID: UUID(), value: SyncValue(event: e))
    do {
      try a.receive(invalid)
      preconditionFailure("Mismatched id must be rejected")
    } catch {}
    expect(
      try a.load() == [e] && a.pendingCount() == 1,
      "Invalid cloud response leaves local data intact")
  }
  func testMagicLinkValidation() throws {
    let client = SupabaseClient(
      configuration: try SupabaseConfiguration(
        url: "https://test.supabase.co", publishableKey: "sb_publishable_TEST_FIXTURE_ONLY"))
    let prefix = "https://test.supabase.co/auth/v1/verify?token=TEST_TOKEN_HASH_1234567890&type="
    let valid = try client.verificationParameters(
      email: "example@example.invalid",
      input: prefix + "magiclink&redirect_to=https%3A%2F%2Funtrusted.invalid")
    expect(
      valid["token_hash"] == "TEST_TOKEN_HASH_1234567890" && valid["redirect_to"] == nil,
      "Only token is verified, no redirect followed")
    expect(
      try client.verificationParameters(email: "example@example.invalid", input: prefix + "signup")[
        "type"] == "signup", "Initial sign-up link supported")
    for value in [
      prefix.replacingOccurrences(of: "test.supabase.co", with: "other.supabase.co") + "magiclink",
      prefix + "recovery", prefix.replacingOccurrences(of: "https:", with: "http:") + "magiclink",
    ] {
      do {
        _ = try client.verificationParameters(email: "example@example.invalid", input: value)
        preconditionFailure("Reject unrelated credential")
      } catch {}
    }
  }
  func testSupabaseConfigurationAndHeaders() throws {
    let config = try SupabaseConfiguration(
      url: "https://example.supabase.co/", publishableKey: "sb_publishable_TEST_FIXTURE_ONLY")
    expect(config.url.absoluteString == "https://example.supabase.co", "Normalize project URL")
    let client = SupabaseClient(configuration: config)
    let request = try client.request(
      path: "rest/v1/monthly_plan_records", token: "TEST_ACCESS_TOKEN")
    expect(
      request.value(forHTTPHeaderField: "Authorization") == "Bearer TEST_ACCESS_TOKEN",
      "Auth is a header")
    expect(
      request.value(forHTTPHeaderField: "apikey") == config.publishableKey,
      "Project key is a header")
    expect(request.url?.query == nil, "No token in URL")
    for key in ["sb_secret_TEST_FIXTURE_ONLY", "not-a-key"] {
      do {
        _ = try SupabaseConfiguration(url: config.url.absoluteString, publishableKey: key)
        preconditionFailure("Reject secret keys")
      } catch {}
    }
    for url in [
      "http://example.supabase.co", "https://example.supabase.co/path",
      "https://user:pass@example.supabase.co", "https://example.supabase.co?token=test",
    ] {
      do {
        _ = try SupabaseConfiguration(url: url, publishableKey: config.publishableKey)
        preconditionFailure("Reject unsafe URL")
      } catch {}
    }
  }
}
