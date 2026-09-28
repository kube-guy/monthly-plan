import Foundation

public struct SyncValue: Codable, Equatable, Sendable {
  public var event: PlanEvent?
  public var placeKey: String?
  public var googlePlaceID: String?
  public init(event: PlanEvent? = nil, placeKey: String? = nil, googlePlaceID: String? = nil) {
    self.event = event
    self.placeKey = placeKey
    self.googlePlaceID = googlePlaceID
  }
}
public struct SyncMutation: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var baseRevision: Int64
  public var mutationID: UUID
  public var value: SyncValue?
  public var deleted: Bool
  public init(id: String, baseRevision: Int64, value: SyncValue?, deleted: Bool = false) {
    self.id = id
    self.baseRevision = baseRevision
    self.mutationID = UUID()
    self.value = value
    self.deleted = deleted
  }
}
public struct SyncRecord: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var revision: Int64
  public var mutationID: UUID
  public var value: SyncValue?
  public var deleted: Bool
  enum CodingKeys: String, CodingKey {
    case id, revision, value, deleted
    case mutationID = "mutation_id"
  }
  public init(
    id: String, revision: Int64, mutationID: UUID, value: SyncValue?, deleted: Bool = false
  ) {
    self.id = id
    self.revision = revision
    self.mutationID = mutationID
    self.value = value
    self.deleted = deleted
  }
  public func validated() throws -> Self {
    guard revision > 0 else { throw PlanError.invalid("동기화 버전이 올바르지 않습니다.") }
    if id.hasPrefix("place:") {
      let key = String(id.dropFirst(6))
      guard key.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
        deleted
          || (value?.placeKey == key && value?.event == nil
            && value?.googlePlaceID?.range(
              of: "^[A-Za-z0-9_-]{1,255}$", options: .regularExpression) != nil)
      else { throw PlanError.invalid("동기화 장소 정보가 올바르지 않습니다.") }
    } else {
      guard let uuid = UUID(uuidString: id), id == uuid.uuidString,
        deleted
          || (value?.event?.id == uuid && value?.placeKey == nil && value?.googlePlaceID == nil)
      else { throw PlanError.invalid("동기화 일정 정보가 올바르지 않습니다.") }
      if !deleted { _ = try value!.event!.validated() }
    }
    return self
  }
}
public struct SyncConflict: Identifiable, Sendable {
  public let local: SyncMutation
  public let remote: SyncRecord
  public var id: String { local.id }
  public var title: String { local.value?.event?.title ?? remote.value?.event?.title ?? "장소 연결" }
}
