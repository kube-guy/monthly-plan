import MapKit
import EventKit
import MonthlyPlanCore
import SwiftUI

private enum ActiveSheet: Identifiable {
  case editor(PlanEvent)
  case detail(PlanEvent)
  case natural, export, settings, cloud
  var id: String {
    switch self {
    case .editor(let e): "edit-\(e.id)"
    case .detail(let e): "detail-\(e.id)"
    case .natural: "natural"
    case .export: "export"
    case .settings: "settings"
    case .cloud: "cloud"
    }
  }
}
struct PlannerView: View {
  @EnvironmentObject var store: PlanStore
  @StateObject private var google = GoogleCalendarStore()
  @StateObject private var directGoogle = DirectGoogleCalendarStore()
  @State private var month = PlanDate.first(Date())
  @State private var selected: String?
  @State private var sheet: ActiveSheet?
  @State private var camera: MapCameraPosition = .automatic
  @State private var pendingDelete: PlanEvent?
  @State private var showDelete = false
  @State private var message = ""
  private var monthKey: String { PlanDate.month(month) }
  private var events: [PlanEvent] {
    let stored = store.events.filter { $0.date.hasPrefix(monthKey) }
    let storedIDs = Set(stored.map(\.id))
    return PlanDate.sorted(stored
      + google.events.filter { !storedIDs.contains($0.id) }
      + directGoogle.events.filter { !storedIDs.contains($0.id) })
  }
  private var googleEventIDs: Set<UUID> {
    Set((google.events + directGoogle.events + store.events.filter {
      $0.calendarOrigin != nil
    }).map(\.id))
  }
  private var visible: [PlanEvent] { events.filter { selected == nil || $0.date == selected } }
  private var mapped: [PlanEvent] { visible.filter(\.hasLocation) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 12) {
            Eyebrow(title: "MY MONTHLY JOURNEY")
            Text("이번 달, 어디로 갈까요?").font(.system(size: 30, weight: .semibold)).tracking(-1)
              .foregroundStyle(Color.ink)
            Text("약속과 일상, 그리고 기대되는 순간들.").font(.system(size: 13)).foregroundStyle(Color.subtle)
          }
          Spacer()
          Button {
            sheet = .natural
          } label: {
            Label("문장으로 추가", systemImage: "text.bubble")
          }.buttonStyle(QuietButtonStyle())
          Button {
            newEvent()
          } label: {
            Label("일정 추가", systemImage: "plus")
          }.buttonStyle(PrimaryButtonStyle())
        }.padding(.vertical, 33)
        if let error = store.error {
          Text(error).font(.caption).foregroundStyle(.red).padding(.bottom, 15)
        }
        if !message.isEmpty {
          Text(message).font(.caption).foregroundStyle(.red).padding(.bottom, 15)
        }
        HStack(alignment: .top, spacing: 22) {
          VStack(spacing: 0) {
            calendarToolbar
            CalendarCard(
              month: month, events: events, selected: selected, externalIDs: googleEventIDs,
              onDay: {
                selected = selected == $0 ? nil : $0
                camera = .automatic
              }, onEvent: { sheet = .detail($0) })
          }.frame(maxWidth: .infinity)
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              VStack(alignment: .leading, spacing: 8) {
                Eyebrow(title: "PLACES THIS MONTH")
                Text(
                  "이달의 발자국 · \(Set(events.filter(\.hasLocation).map{String(format:"%.5f,%.5f",$0.latitude!,$0.longitude!)}).count)"
                ).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.ink)
              }
              Spacer()
              Image(systemName: "location.north.circle").font(.title2).foregroundStyle(Color.subtle)
            }.padding(22)
            map.frame(height: 260)
            HStack {
              Text("기본 지도 · Apple 지도")
              Spacer()
              Text("장소 상세에서 네이버지도 열기 ↗")
            }.font(.system(size: 9)).foregroundStyle(Color.subtle).padding(10).background(
              Color(hex: 0xF4F6EE))
            HStack {
              Text(selected.map { "\(Int($0.suffix(2)) ?? 0)일의 순간들" } ?? "이달의 순간들").font(
                .system(size: 13, weight: .semibold))
              Text("\(visible.count)").foregroundStyle(Color.subtle).font(.caption)
              Spacer()
              if selected != nil {
                Button {
                  selected = nil
                  camera = .automatic
                } label: {
                  Image(systemName: "xmark")
                }.buttonStyle(.plain)
              }
            }.padding(.horizontal, 22).padding(.top, 22)
            ScrollView {
              MomentsList(events: visible, externalIDs: googleEventIDs, onSelect: { sheet = .detail($0) }).padding(
                .horizontal, 22)
            }.frame(maxHeight: 330)
          }.frame(width: 370).background(.white, in: RoundedRectangle(cornerRadius: 13)).overlay(
            RoundedRectangle(cornerRadius: 13).stroke(Color.line))
        }
        HStack {
          Text("monthly-plan · 한 달을 거닐다")
          Spacer()
          Text(store.syncStatus).lineLimit(2)
        }.font(.system(size: 10)).foregroundStyle(Color.subtle).padding(.vertical, 24)
      }.padding(.horizontal, 32)
    }.background(Color.paper)
      .task {
        google.setMonth(month)
        directGoogle.setMonth(month)
        while !Task.isCancelled {
          await store.sync()
          do { try await Task.sleep(for: .seconds(60)) } catch { break }
        }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
        Task { await store.sync() }
        google.refresh()
        directGoogle.refresh()
      }
      .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
        google.refresh()
      }
      .onChange(of: google.events) { _, values in
        if store.calendarSyncEnabled && google.authorized && !google.selectedIDs.isEmpty {
          store.mirrorCalendarEvents(values)
        }
      }
      .onChange(of: store.calendarSyncEnabled) { _, enabled in
        if enabled && google.authorized && !google.selectedIDs.isEmpty {
          store.mirrorCalendarEvents(google.events)
        }
      }
      .onChange(of: store.calendarSyncMode) { _, _ in
        if store.calendarSyncEnabled && google.authorized && !google.selectedIDs.isEmpty {
          store.mirrorCalendarEvents(google.events)
        }
      }
      .onChange(of: store.selectedCalendarUIDs) { _, _ in
        if store.calendarSyncEnabled && google.authorized && !google.selectedIDs.isEmpty {
          store.mirrorCalendarEvents(google.events)
        }
      }
      .onChange(of: store.accountID) { _, _ in
        selected = nil
        sheet = nil
        camera = .automatic
        if store.calendarSyncEnabled && google.authorized && !google.selectedIDs.isEmpty {
          store.mirrorCalendarEvents(google.events)
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .newPlan)) { _ in newEvent() }
      .onChange(of: month) { _, _ in
        selected = nil
        camera = .automatic
        google.setMonth(month)
        directGoogle.setMonth(month)
      }
      .sheet(item: $sheet) { item in
        switch item {
        case .editor(let event):
          EventEditor(initial: event) {
            try store.save([$0])
            didSave($0)
          }
        case .natural:
          NaturalEntrySheet { values in
            try store.save(values)
            if let first = values.first { didSave(first) }
          }
        case .settings: PlacesSettings()
        case .cloud: CloudSettings().environmentObject(google).environmentObject(directGoogle)
        case .export: ExportSheet(events: events, month: month)
        case .detail(let event):
          EventDetail(
            event: event, readOnly: googleEventIDs.contains(event.id),
            sourceLabel: directGoogle.events.contains(where: { $0.id == event.id })
              ? "Google Calendar · 읽기 전용" : "Mac 캘린더 · 읽기 전용",
            onEdit: { sheet = .editor(event) },
            onDelete: {
              pendingDelete = event
              sheet = nil
              showDelete = true
            })
        }
      }
      .confirmationDialog("이 일정을 삭제할까요?", isPresented: $showDelete, titleVisibility: .visible) {
        Button("삭제", role: .destructive) {
          if let e = pendingDelete {
            do { try store.delete(e) } catch { message = error.localizedDescription }
          }
        }
        Button("취소", role: .cancel) {}
      } message: {
        Text(pendingDelete?.title ?? "")
      }
  }
  private var header: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 11).fill(Color.forest).frame(width: 35, height: 39)
        Image(systemName: "mappin").foregroundStyle(.white).font(.title2)
      }
      Text("monthly-plan").font(.system(size: 20, weight: .semibold)).tracking(-0.8)
      Spacer()
      Text("나의 일정을, 나만의 지도로.").font(.system(size: 11)).foregroundStyle(Color.subtle)
      Button {
        sheet = .cloud
      } label: {
        Label(
          store.signedIn ? "계정 · 동기화" : "클라우드 연결",
          systemImage: store.signedIn ? "icloud.fill" : "icloud")
      }.buttonStyle(QuietButtonStyle())
      Button {
        sheet = .settings
      } label: {
        Image(systemName: "gearshape")
      }.buttonStyle(QuietButtonStyle())
      Button {
        sheet = .export
      } label: {
        Label("이미지 내보내기", systemImage: "square.and.arrow.up")
      }.buttonStyle(QuietButtonStyle())
    }.padding(.vertical, 22).overlay(alignment: .bottom) { Color.line.frame(height: 1) }
  }
  private var calendarToolbar: some View {
    HStack(spacing: 15) {
      Text(monthKey.replacingOccurrences(of: "-", with: ".")).font(
        .system(size: 28, weight: .medium)
      ).foregroundStyle(Color.ink)
      Button {
        move(-1)
      } label: {
        Image(systemName: "chevron.left")
      }.disabled(monthKey == "1900-01")
      Button {
        move(1)
      } label: {
        Image(systemName: "chevron.right")
      }.disabled(monthKey == "2100-12")
      Button("오늘") {
        month = PlanDate.first(Date())
        selected = nil
      }.font(.system(size: 11))
      Spacer()
      Button {
        sheet = .cloud
      } label: {
        Label("Google Calendar", systemImage: "calendar")
      }.font(.system(size: 11))
      Text("일정 \(events.count)개").font(.system(size: 11)).foregroundStyle(Color.subtle)
    }.buttonStyle(.plain).padding(.horizontal, 22).padding(.vertical, 23).background(
      .white, in: RoundedRectangle(cornerRadius: 12))
  }
  private var map: some View {
    Map(position: $camera) {
      ForEach(mapped) { event in
        Annotation(
          event.place.isEmpty ? event.title : event.place,
          coordinate: CLLocationCoordinate2D(latitude: event.latitude!, longitude: event.longitude!)
        ) {
          Button {
            sheet = .detail(event)
          } label: {
            Image(systemName: "mappin.circle.fill").font(.system(size: 29)).foregroundStyle(
              event.category.color, .white
            ).shadow(radius: 2)
          }.buttonStyle(.plain)
        }
      }
    }
    .mapControls {
      MapZoomStepper()
      MapCompass()
    }
    .overlay {
      if mapped.isEmpty {
        Text("장소를 선택한 일정이 지도에 표시돼요.").font(.system(size: 11)).padding(10).background(
          .regularMaterial, in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }
  private func move(_ value: Int) {
    if let next = PlanDate.calendar.date(byAdding: .month, value: value, to: month) { month = next }
  }
  private func newEvent() {
    sheet = .editor(
      PlanEvent(
        date: selected
          ?? (PlanDate.month(Date()) == monthKey ? PlanDate.string(Date()) : monthKey + "-01")))
  }
  private func didSave(_ event: PlanEvent) {
    month = PlanDate.first(PlanDate.parse(event.date)!)
    selected = nil
    message = ""
    camera = .automatic
  }
}
struct EventDetail: View {
  let event: PlanEvent
  var readOnly = false
  var sourceLabel = "Mac 캘린더 · 읽기 전용"
  let onEdit: () -> Void
  let onDelete: () -> Void
  @Environment(\.dismiss) var dismiss
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 19) {
        HStack {
          if readOnly {
            Label(sourceLabel, systemImage: "calendar").font(.caption)
              .foregroundStyle(Color.subtle)
          }
          Text(event.category.label).font(.caption).padding(7).foregroundStyle(event.category.color)
            .background(event.category.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }.buttonStyle(.plain)
        }
        Text(event.title).font(.title2.weight(.semibold))
        Label(
          "\(event.date) · \(event.displayTime)\(event.endTime.isEmpty ? "":" – "+event.endTime)",
          systemImage: "clock"
        ).font(.system(size: 13)).foregroundStyle(Color.subtle)
        Label(event.place.isEmpty ? "장소 미정" : event.place, systemImage: "mappin")
        if !event.address.isEmpty {
          Text(event.address).font(.caption).foregroundStyle(Color.subtle)
        }
        if let url = event.naverURL {
          Link(destination: url) { Label("네이버지도에서 장소 찾기", systemImage: "arrow.up.right") }.font(
            .system(size: 13)
          ).tint(Color.forest)
        }
        if !readOnly && !event.hasLocation && !event.place.isEmpty {
          Text("일정 수정에서 장소를 찾으면 지도에도 표시됩니다.").font(.caption).foregroundStyle(Color.subtle)
        }
        if !event.notes.isEmpty {
          Text(event.notes).font(.system(size: 13)).textSelection(.enabled)
        }
        if !readOnly {
          Divider()
          ExternalPlacesView(event: event)
          HStack {
            Button("삭제", role: .destructive, action: onDelete)
            Spacer()
            Button("수정", action: onEdit).buttonStyle(PrimaryButtonStyle())
          }
        }
      }.padding(30)
    }.frame(width: 560, height: 680).foregroundStyle(Color.ink).background(Color.paper)
  }
}
