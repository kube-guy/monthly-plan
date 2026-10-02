import Foundation

public enum CalendarSyncMode: String, Codable, Sendable {
  case all
  case selected
}

public enum CalendarSyncSelection {
  public static func events(_ values: [PlanEvent], mode: CalendarSyncMode,
    selectedUIDs: Set<String>) -> [PlanEvent] {
    values.filter { event in
      guard let origin = event.calendarOrigin, origin.provider == "mac-calendar" else {
        return false
      }
      return mode == .all || selectedUIDs.contains(origin.uid)
    }
  }
}
