import CryptoKit
import Foundation

public struct CalendarImportInput: Sendable {
  public var externalID: String
  public var occurrenceDate: Date?
  public var start: Date
  public var end: Date
  public var modifiedAt: Date?
  public var title: String
  public var location: String
  public var notes: String
  public var isAllDay: Bool
  public var latitude: Double?
  public var longitude: Double?

  public init(externalID: String, occurrenceDate: Date? = nil, start: Date, end: Date,
    modifiedAt: Date? = nil, title: String, location: String = "", notes: String = "",
    isAllDay: Bool = false, latitude: Double? = nil, longitude: Double? = nil) {
    self.externalID = externalID
    self.occurrenceDate = occurrenceDate
    self.start = start
    self.end = end
    self.modifiedAt = modifiedAt
    self.title = title
    self.location = location
    self.notes = notes
    self.isAllDay = isAllDay
    self.latitude = latitude
    self.longitude = longitude
  }
}

public enum CalendarImport {
  public static func place(title: String, location: String) -> String {
    let explicit = location.trimmingCharacters(in: .whitespacesAndNewlines)
    if !explicit.isEmpty { return String(explicit.prefix(200)) }
    let patterns = [
      #"(?:장소|위치)\s*[:：]\s*([^,;|]{2,80})"#,
      #"@\s*([^@,;|]{2,80})\s*$"#,
      #"^([^,;|]{2,60}?)에서(?:\s|$)"#,
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: title,
          range: NSRange(title.startIndex..., in: title)),
        let range = Range(match.range(at: 1), in: title) else { continue }
      let candidate = title[range].trimmingCharacters(in: .whitespacesAndNewlines)
      if !candidate.isEmpty { return candidate }
    }
    return ""
  }

  public static func plans(_ input: CalendarImportInput, from monthStart: Date,
    until monthEnd: Date) -> [PlanEvent] {
    guard !input.externalID.isEmpty, input.end > input.start,
      input.start < monthEnd, input.end > monthStart else { return [] }
    let anchor = input.occurrenceDate.map { String($0.timeIntervalSince1970) } ?? "single"
    let uid = digest("mac-calendar|\(input.externalID)|\(anchor)")
    let origin = CalendarOrigin(uid: uid,
      updatedAt: max(0, input.modifiedAt?.timeIntervalSince1970 ?? 0))
    let finalInstant = input.end.addingTimeInterval(-0.001)
    var day = PlanDate.calendar.startOfDay(for: max(input.start, monthStart))
    let lastDay = PlanDate.calendar.startOfDay(for:
      min(finalInstant, monthEnd.addingTimeInterval(-0.001)))
    var result: [PlanEvent] = []
    let title = String((input.title.isEmpty ? "제목 없는 일정" : input.title).prefix(100))
    let extracted = place(title: title, location: input.location)
    let notes = String(input.notes.prefix(2000))
    let validCoordinates = input.latitude != nil && input.longitude != nil
      && abs(input.latitude!) <= 85 && abs(input.longitude!) <= 180
    while day <= lastDay {
      let date = PlanDate.string(day)
      let first = PlanDate.calendar.isDate(day, inSameDayAs: input.start)
      let allDay = input.isAllDay || !first
      let startParts = PlanDate.calendar.dateComponents([.hour, .minute], from: input.start)
      let endParts = PlanDate.calendar.dateComponents([.hour, .minute], from: input.end)
      let time = allDay ? "00:00" : String(format: "%02d:%02d",
        startParts.hour ?? 0, startParts.minute ?? 0)
      let endTime = first && !input.isAllDay
        && PlanDate.calendar.isDate(input.start, inSameDayAs: input.end)
        ? String(format: "%02d:%02d", endParts.hour ?? 0, endParts.minute ?? 0) : ""
      let eventID = uuid(digest(uid + "|" + date))
      result.append(PlanEvent(id: eventID, title: title, date: date, time: time,
        endTime: endTime, place: extracted, notes: notes,
        latitude: validCoordinates ? input.latitude : nil,
        longitude: validCoordinates ? input.longitude : nil,
        isAllDay: allDay, calendarOrigin: origin))
      guard let next = PlanDate.calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    return result
  }

  private static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func uuid(_ hex: String) -> UUID {
    UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))")!
  }
}
