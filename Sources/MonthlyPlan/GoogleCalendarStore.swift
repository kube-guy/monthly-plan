import CryptoKit
import EventKit
import MonthlyPlanCore
import SwiftUI

/// Reads calendars already connected to macOS. These events are never written to PlanStore.
@MainActor
final class GoogleCalendarStore: ObservableObject {
  struct CalendarChoice: Identifiable {
    let id: String
    let title: String
    let account: String
    let color: Color
  }

  @Published private(set) var calendars: [CalendarChoice] = []
  @Published private(set) var events: [PlanEvent] = []
  @Published private(set) var selectedIDs: Set<String>
  @Published private(set) var authorized = false
  @Published private(set) var error: String?

  private let eventStore = EKEventStore()
  private let selectionKey = "monthly-plan.google-calendar-selection"
  private var month = PlanDate.first(Date())

  init() {
    selectedIDs = Set(UserDefaults.standard.stringArray(forKey: selectionKey) ?? [])
    refresh()
  }

  func requestAccess() async {
    do {
      let granted = try await eventStore.requestFullAccessToEvents()
      if !granted { error = "캘린더 읽기 권한을 허용해야 일정을 표시할 수 있어요." }
      refresh()
    } catch {
      self.error = error.localizedDescription
      refresh()
    }
  }

  func setMonth(_ value: Date) {
    month = PlanDate.first(value)
    refresh()
  }

  func toggle(_ id: String) {
    if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    UserDefaults.standard.set(selectedIDs.sorted(), forKey: selectionKey)
    refresh()
  }

  func refresh() {
    authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    guard authorized else {
      calendars = []
      events = []
      return
    }
    error = nil
    let systemCalendars = eventStore.calendars(for: .event)
    calendars = systemCalendars.map {
      CalendarChoice(
        id: $0.calendarIdentifier, title: $0.title,
        account: $0.source.title, color: Color(cgColor: $0.cgColor))
    }.sorted { ($0.account, $0.title, $0.id) < ($1.account, $1.title, $1.id) }
    let selected = systemCalendars.filter { selectedIDs.contains($0.calendarIdentifier) }
    guard !selected.isEmpty else {
      events = []
      return
    }
    let start = PlanDate.first(month)
    guard let end = PlanDate.calendar.date(byAdding: .month, value: 1, to: start) else { return }
    let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
    events = PlanDate.sorted(
      eventStore.events(matching: predicate).flatMap { event in
        overlays(for: event, from: start, until: end)
      })
  }

  private func overlays(for event: EKEvent, from monthStart: Date, until monthEnd: Date) -> [PlanEvent] {
    // A multi-day occurrence appears on each day it occupies. EventKit already expands recurrences.
    guard let eventStart = event.startDate, let eventEnd = event.endDate else { return [] }
    let lastInstant = eventEnd > eventStart
      ? eventEnd.addingTimeInterval(-0.001) : eventStart
    let firstDay = PlanDate.calendar.startOfDay(for: max(eventStart, monthStart))
    let lastDay = PlanDate.calendar.startOfDay(for: min(lastInstant, monthEnd.addingTimeInterval(-0.001)))
    guard firstDay <= lastDay else { return [] }
    var day = firstDay
    var result: [PlanEvent] = []
    while day <= lastDay {
      let first = PlanDate.calendar.isDate(day, inSameDayAs: eventStart)
      let allDay = event.isAllDay || !first
      let date = PlanDate.string(day)
      let occurrence = event.eventIdentifier ?? event.calendarItemIdentifier
      let identity = "\(event.calendar.calendarIdentifier)|\(occurrence)|\(eventStart.timeIntervalSince1970)|\(date)"
      result.append(PlanEvent(
        id: stableID(identity), title: event.title ?? "제목 없는 일정", date: date,
        time: allDay ? "00:00" : clock(eventStart),
        endTime: first && !event.isAllDay && PlanDate.calendar.isDate(eventStart, inSameDayAs: eventEnd)
          ? clock(eventEnd) : "",
        place: event.location ?? "", notes: event.notes ?? "", isAllDay: allDay))
      guard let next = PlanDate.calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    return result
  }

  private func clock(_ date: Date) -> String {
    let parts = PlanDate.calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
  }

  private func stableID(_ text: String) -> UUID {
    let hex = SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
    return UUID(uuidString: value)!
  }
}
