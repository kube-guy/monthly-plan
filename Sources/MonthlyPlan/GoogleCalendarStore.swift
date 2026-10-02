import EventKit
@preconcurrency import MapKit
import MonthlyPlanCore
import SwiftUI

/// Reads calendars already connected to macOS. Selected events can be mirrored to PlanStore.
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
  private(set) var month = PlanDate.first(Date())
  private var placeLookup: Task<Void, Never>?
  private var searchedPlaces = Set<String>()
  private var resolvedPlaces: [String: (latitude: Double, longitude: Double, address: String)] = [:]

  init() {
    selectedIDs = Set(UserDefaults.standard.stringArray(forKey: selectionKey) ?? [])
    refresh()
  }

  func requestAccess() {
    eventStore.requestFullAccessToEvents { [weak self] granted, requestError in
      let message = requestError?.localizedDescription
      Task { @MainActor in
        guard let self else { return }
        if let message { self.error = message }
        else if !granted { self.error = "캘린더 읽기 권한을 허용해야 일정을 표시할 수 있어요." }
        self.refresh()
      }
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
    placeLookup?.cancel()
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
    var seen = Set<UUID>()
    let sourceEvents = eventStore.events(matching: predicate).sorted {
      ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast)
    }
    var imported = PlanDate.sorted(sourceEvents.flatMap { event in
      overlays(for: event, from: start, until: end)
    }.filter { seen.insert($0.id).inserted })
    for index in imported.indices {
      if !imported[index].hasLocation,
        let resolved = resolvedPlaces[imported[index].place] {
        imported[index].latitude = resolved.latitude
        imported[index].longitude = resolved.longitude
        imported[index].address = resolved.address
      }
    }
    events = imported
    let names = Array(Set(events.filter { !$0.place.isEmpty && !$0.hasLocation }
      .map(\.place)).subtracting(searchedPlaces)).sorted().prefix(12)
    let targetMonth = month
    placeLookup = Task { await resolvePlaces(Array(names), month: targetMonth) }
  }

  private func resolvePlaces(_ names: [String], month targetMonth: Date) async {
    for name in names {
      guard !Task.isCancelled, month == targetMonth else { return }
      searchedPlaces.insert(name)
      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = name
      let result = try? await MKLocalSearch(request: request).start()
      guard !Task.isCancelled, month == targetMonth else { return }
      guard let result else { continue }
      guard let item = result.mapItems.first(where: {
        $0.name?.localizedCaseInsensitiveCompare(name) == .orderedSame
      }) else { continue }
      let coordinate = item.placemark.coordinate
      guard abs(coordinate.latitude) <= 85, abs(coordinate.longitude) <= 180 else { continue }
      let address = String((item.placemark.title ?? "").prefix(300))
      resolvedPlaces[name] = (coordinate.latitude, coordinate.longitude, address)
      var updated = events
      for index in updated.indices where updated[index].place == name && !updated[index].hasLocation {
        updated[index].latitude = coordinate.latitude
        updated[index].longitude = coordinate.longitude
        updated[index].address = address
      }
      events = updated
    }
  }

  private func overlays(for event: EKEvent, from monthStart: Date, until monthEnd: Date) -> [PlanEvent] {
    guard let eventStart = event.startDate, let eventEnd = event.endDate else { return [] }
    let coordinate = event.structuredLocation?.geoLocation?.coordinate
    return CalendarImport.plans(CalendarImportInput(
      externalID: event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier,
      occurrenceDate: event.occurrenceDate, start: eventStart, end: eventEnd,
      modifiedAt: event.lastModifiedDate, title: event.title ?? "제목 없는 일정",
      location: event.location ?? "", notes: event.notes ?? "", isAllDay: event.isAllDay,
      latitude: coordinate?.latitude, longitude: coordinate?.longitude),
      from: monthStart, until: monthEnd)
  }
}
