import Foundation

public enum PlanCategory: String, Codable, CaseIterable, Sendable {
  case personal, work, culture, trip
  public var label: String {
    switch self {
    case .personal: "일상"
    case .work: "업무"
    case .culture: "문화"
    case .trip: "여행"
    }
  }
  public var hex: UInt {
    switch self {
    case .personal: 0x638B64
    case .work: 0x617BA8
    case .culture: 0xAA82A3
    case .trip: 0xC39351
    }
  }
}
public struct PlanEvent: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var date: String
  public var time: String
  public var endTime: String
  public var place: String
  public var address: String
  public var category: PlanCategory
  public var notes: String
  public var latitude: Double?
  public var longitude: Double?
  public init(
    id: UUID = UUID(), title: String = "", date: String = "", time: String = "10:00",
    endTime: String = "", place: String = "", address: String = "",
    category: PlanCategory = .personal, notes: String = "", latitude: Double? = nil,
    longitude: Double? = nil
  ) {
    self.id = id
    self.title = title
    self.date = date
    self.time = time
    self.endTime = endTime
    self.place = place
    self.address = address
    self.category = category
    self.notes = notes
    self.latitude = latitude
    self.longitude = longitude
  }
  public var hasLocation: Bool { latitude != nil && longitude != nil }
  public var naverURL: URL? {
    let query = address.isEmpty ? place : address
    guard !query.isEmpty else { return nil }
    return URL(string: "https://map.naver.com/p/search/")?.appendingPathComponent(query)
  }
  public func validated() throws -> PlanEvent {
    var result = self
    result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    result.place = place.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !result.title.isEmpty && result.title.count <= 100 else {
      throw PlanError.invalid("일정 이름을 1~100자로 입력해 주세요.")
    }
    guard PlanDate.parse(date) != nil else {
      throw PlanError.invalid("유효한 날짜를 YYYY-MM-DD 형식으로 입력해 주세요.")
    }
    guard PlanDate.validTime(time),
      endTime.isEmpty || (PlanDate.validTime(endTime) && endTime > time)
    else { throw PlanError.invalid("시간은 HH:mm 형식이며, 종료는 같은 날의 시작보다 늦어야 해요.") }
    guard place.count <= 200, address.count <= 300, notes.count <= 2000 else {
      throw PlanError.invalid("장소·주소·메모가 너무 깁니다.")
    }
    if latitude != nil || longitude != nil {
      guard let lat = latitude, let lng = longitude, lat.isFinite, lng.isFinite, abs(lat) <= 85,
        abs(lng) <= 180
      else { throw PlanError.invalid("지도 위치를 다시 선택해 주세요.") }
    }
    return result
  }
}
public enum PlanError: LocalizedError {
  case invalid(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let message): message
    }
  }
}
public enum PlanDate {
  public static var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "Asia/Seoul")!
    value.firstWeekday = 1
    return value
  }
  public static func string(_ date: Date) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
  }
  public static func parse(_ value: String) -> Date? {
    guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
      return nil
    }
    let p = value.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3, (1900...2100).contains(p[0]),
      let date = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)),
      string(date) == value
    else { return nil }
    return date
  }
  public static func month(_ date: Date) -> String { String(string(date).prefix(7)) }
  public static func first(_ date: Date) -> Date {
    calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
  }
  public static func addingDays(_ count: Int, to date: Date) -> Date {
    calendar.date(byAdding: .day, value: count, to: date)!
  }
  public static func validTime(_ text: String) -> Bool {
    text.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil
  }
  public static func sorted(_ values: [PlanEvent]) -> [PlanEvent] {
    values.sorted { ($0.date, $0.time, $0.id.uuidString) < ($1.date, $1.time, $1.id.uuidString) }
  }
}
