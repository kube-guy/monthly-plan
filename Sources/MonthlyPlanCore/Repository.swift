import CryptoKit
import Foundation
import SQLite3

extension PlanEvent {
  public var placeKey: String {
    let normalize: (String) -> String = {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
        of: #"\s+"#, with: " ", options: .regularExpression
      ).lowercased()
    }
    return SHA256.hash(data: Data((normalize(place) + "|" + normalize(address)).utf8)).map {
      String(format: "%02x", $0)
    }.joined()
  }
}
public final class EventRepository {
  public let fileURL: URL
  private var db: OpaquePointer?
  public init(fileURL: URL, legacyURL: URL? = nil) throws {
    self.fileURL = fileURL
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
      sqlite3_open_v2(
        fileURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK
    else {
      sqlite3_close(db)
      db = nil
      throw PlanError.invalid("일정 데이터베이스를 열지 못했습니다.")
    }
    do {
      sqlite3_busy_timeout(db, 5000)
      try execute("PRAGMA journal_mode = WAL")
      let version =
        try query("PRAGMA user_version").first.flatMap { $0.first }.flatMap(Int.init) ?? 0
      guard version <= 2 else {
        throw PlanError.invalid("더 새로운 앱에서 만든 데이터입니다. monthly-plan을 업데이트해 주세요.")
      }
      if version == 0 {
        try transaction {
          try execute(
            "CREATE TABLE events (id TEXT PRIMARY KEY NOT NULL, date TEXT NOT NULL, time TEXT NOT NULL, payload TEXT NOT NULL)"
          )
          try execute("CREATE INDEX idx_events_date_time ON events(date,time)")
          try execute(
            "CREATE TABLE external_places (place_key TEXT PRIMARY KEY NOT NULL, google_place_id TEXT NOT NULL)"
          )
          try execute("CREATE TABLE metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
          try execute("PRAGMA user_version = 1")
        }
      }
      if version < 2 {
        try transaction {
          try execute(
            "CREATE TABLE sync_state (id TEXT PRIMARY KEY NOT NULL, revision INTEGER NOT NULL)")
          try execute(
            "CREATE TABLE sync_queue (id TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)")
          try execute(
            "CREATE TABLE sync_conflicts (id TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)")
          for event in try load() {
            try enqueue(id: event.id.uuidString, value: SyncValue(event: event))
          }
          for row in try query("SELECT place_key,google_place_id FROM external_places") {
            try enqueue(
              id: "place:" + row[0], value: SyncValue(placeKey: row[0], googlePlaceID: row[1]))
          }
          try execute("PRAGMA user_version = 2")
        }
      }
      if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path),
        try query("SELECT value FROM metadata WHERE key = 'legacy_imported'").isEmpty
      {
        let old = try JSONDecoder().decode([PlanEvent].self, from: Data(contentsOf: legacyURL))
        let checked = try validateBatch(old)
        try transaction {
          try upsert(checked)
          for event in checked {
            try enqueue(id: event.id.uuidString, value: SyncValue(event: event))
          }
          try execute("INSERT INTO metadata(key,value) VALUES('legacy_imported','1')")
        }
      }
    } catch {
      sqlite3_close(db)
      db = nil
      throw error
    }
  }
  deinit { sqlite3_close(db) }
  public func load() throws -> [PlanEvent] {
    try query("SELECT payload FROM events ORDER BY date,time,id").map { row in
      try JSONDecoder().decode(PlanEvent.self, from: Data(row[0].utf8)).validated()
    }
  }
  public func save(_ events: [PlanEvent]) throws {
    let checked = try validateBatch(events)
    try transaction {
      try upsert(checked)
      for event in checked { try enqueue(id: event.id.uuidString, value: SyncValue(event: event)) }
    }
  }
  public func delete(id: UUID) throws {
    try transaction {
      try execute("DELETE FROM events WHERE id = ?", [id.uuidString])
      try enqueue(id: id.uuidString, value: nil, deleted: true)
    }
  }
  public func externalPlaceID(for event: PlanEvent) throws -> String? {
    try query("SELECT google_place_id FROM external_places WHERE place_key = ?", [event.placeKey])
      .first?.first
  }
  public func linkExternalPlace(id: String, to event: PlanEvent) throws {
    guard id.range(of: #"^[A-Za-z0-9_-]{1,255}$"#, options: .regularExpression) != nil else {
      throw PlanError.invalid("잘못된 장소 식별자입니다.")
    }
    try transaction {
      try execute(
        "INSERT INTO external_places(place_key,google_place_id) VALUES(?,?) ON CONFLICT(place_key) DO UPDATE SET google_place_id = excluded.google_place_id",
        [event.placeKey, id])
      try enqueue(
        id: "place:" + event.placeKey, value: SyncValue(placeKey: event.placeKey, googlePlaceID: id)
      )
    }
  }
  public func unlinkExternalPlace(for event: PlanEvent) throws {
    try transaction {
      try execute("DELETE FROM external_places WHERE place_key = ?", [event.placeKey])
      try enqueue(id: "place:" + event.placeKey, value: nil, deleted: true)
    }
  }
  public func pending() throws -> [SyncMutation] {
    try query(
      "SELECT payload FROM sync_queue WHERE id NOT IN (SELECT id FROM sync_conflicts) ORDER BY id"
    ).map {
      try JSONDecoder().decode(SyncMutation.self, from: Data($0[0].utf8))
    }
  }
  public func pendingCount() throws -> Int {
    Int(try query("SELECT count(*) FROM sync_queue")[0][0]) ?? 0
  }
  public func conflicts() throws -> [SyncConflict] {
    try query(
      "SELECT q.payload,c.payload FROM sync_queue q JOIN sync_conflicts c ON q.id=c.id ORDER BY q.id"
    ).map {
      SyncConflict(
        local: try JSONDecoder().decode(SyncMutation.self, from: Data($0[0].utf8)),
        remote: try JSONDecoder().decode(SyncRecord.self, from: Data($0[1].utf8)))
    }
  }
  // A response may arrive after another edit. Only acknowledge the mutation actually sent.
  public func receive(_ incoming: SyncRecord, sent: SyncMutation? = nil) throws {
    let remote = try incoming.validated()
    try transaction {
      let known = try revision(for: remote.id)
      guard remote.revision > known else { return }
      if let row = try query("SELECT payload FROM sync_conflicts WHERE id = ?", [remote.id]).first {
        let previous = try JSONDecoder().decode(SyncRecord.self, from: Data(row[0].utf8))
        guard remote.revision >= previous.revision else { return }
      }
      if let local = try queued(remote.id) {
        if local.mutationID == remote.mutationID {
          try clearPending(remote.id)
          try install(remote)
        } else if let sent, sent.id == remote.id, sent.mutationID == remote.mutationID,
          local.baseRevision == sent.baseRevision
        {
          var rebased = local
          rebased.baseRevision = remote.revision
          try setQueue(rebased)
          try setRevision(remote)
        } else if remote.revision > local.baseRevision {
          try execute(
            "INSERT INTO sync_conflicts(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",
            [remote.id, try json(remote)])
        }
      } else {
        try install(remote)
      }
    }
  }
  public func resolve(id: String, keepLocal: Bool) throws {
    try transaction {
      guard let row = try query("SELECT payload FROM sync_conflicts WHERE id = ?", [id]).first,
        let local = try queued(id)
      else { return }
      let remote = try JSONDecoder().decode(SyncRecord.self, from: Data(row[0].utf8)).validated()
      if keepLocal {
        try setRevision(remote)
        try setQueue(
          SyncMutation(
            id: id, baseRevision: remote.revision, value: local.value, deleted: local.deleted))
        try execute("DELETE FROM sync_conflicts WHERE id = ?", [id])
      } else {
        try clearPending(id)
        try install(remote)
      }
    }
  }
  private func enqueue(id: String, value: SyncValue?, deleted: Bool = false) throws {
    let base = try queued(id)?.baseRevision ?? revision(for: id)
    try setQueue(SyncMutation(id: id, baseRevision: base, value: value, deleted: deleted))
  }
  private func queued(_ id: String) throws -> SyncMutation? {
    guard let row = try query("SELECT payload FROM sync_queue WHERE id = ?", [id]).first else {
      return nil
    }
    return try JSONDecoder().decode(SyncMutation.self, from: Data(row[0].utf8))
  }
  private func revision(for id: String) throws -> Int64 {
    Int64(try query("SELECT revision FROM sync_state WHERE id = ?", [id]).first?.first ?? "0") ?? 0
  }
  private func setQueue(_ value: SyncMutation) throws {
    try execute(
      "INSERT INTO sync_queue(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",
      [value.id, try json(value)])
  }
  private func setRevision(_ remote: SyncRecord) throws {
    try execute(
      "INSERT INTO sync_state(id,revision) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision",
      [remote.id, String(remote.revision)])
  }
  private func clearPending(_ id: String) throws {
    try execute("DELETE FROM sync_queue WHERE id = ?", [id])
    try execute("DELETE FROM sync_conflicts WHERE id = ?", [id])
  }
  private func install(_ remote: SyncRecord) throws {
    if remote.id.hasPrefix("place:") {
      let key = String(remote.id.dropFirst(6))
      if remote.deleted {
        try execute("DELETE FROM external_places WHERE place_key = ?", [key])
      } else {
        try execute(
          "INSERT INTO external_places(place_key,google_place_id) VALUES(?,?) ON CONFLICT(place_key) DO UPDATE SET google_place_id=excluded.google_place_id",
          [key, remote.value!.googlePlaceID!])
      }
    } else if remote.deleted {
      try execute("DELETE FROM events WHERE id = ?", [remote.id])
    } else {
      try upsert([remote.value!.event!])
    }
    try setRevision(remote)
  }
  private func json<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }
  private func validateBatch(_ values: [PlanEvent]) throws -> [PlanEvent] {
    let checked = try values.map { try $0.validated() }
    guard Set(checked.map(\.id)).count == checked.count else {
      throw PlanError.invalid("중복 일정이 있습니다.")
    }
    return checked
  }
  private func upsert(_ values: [PlanEvent]) throws {
    for event in values {
      let data = try JSONEncoder().encode(event)
      try execute(
        "INSERT INTO events(id,date,time,payload) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET date=excluded.date,time=excluded.time,payload=excluded.payload",
        [event.id.uuidString, event.date, event.time, String(decoding: data, as: UTF8.self)])
    }
  }
  private func transaction(_ operation: () throws -> Void) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      try operation()
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
  private func prepare(_ sql: String, _ values: [String]) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw failure()
    }
    for (index, value) in values.enumerated() {
      if sqlite3_bind_text(
        statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        != SQLITE_OK
      {
        sqlite3_finalize(statement)
        throw failure()
      }
    }
    return statement
  }
  private func execute(_ sql: String, _ values: [String] = []) throws {
    let statement = try prepare(sql, values)
    defer { sqlite3_finalize(statement) }
    var status = sqlite3_step(statement)
    while status == SQLITE_ROW { status = sqlite3_step(statement) }
    guard status == SQLITE_DONE else { throw failure() }
  }
  private func query(_ sql: String, _ values: [String] = []) throws -> [[String]] {
    let statement = try prepare(sql, values)
    defer { sqlite3_finalize(statement) }
    var rows: [[String]] = []
    var status = sqlite3_step(statement)
    while status == SQLITE_ROW {
      var row: [String] = []
      for index in 0..<sqlite3_column_count(statement) {
        row.append(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "")
      }
      rows.append(row)
      status = sqlite3_step(statement)
    }
    guard status == SQLITE_DONE else { throw failure() }
    return rows
  }
  private func failure() -> PlanError {
    .invalid("데이터 저장소 오류: \(db.map{String(cString:sqlite3_errmsg($0))} ?? "연결 없음")")
  }
}
