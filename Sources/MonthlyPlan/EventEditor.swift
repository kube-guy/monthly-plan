// Older macOS SDKs lack MapKit's Sendable annotations; search results stay on MainActor.
@preconcurrency import MapKit
import MonthlyPlanCore
import SwiftUI

struct EventEditor: View {
  @Environment(\.dismiss) var dismiss
  @State private var event: PlanEvent
  @State private var error = ""
  @State private var searching = false
  @State private var results: [MKMapItem] = []
  @State private var request: MKLocalSearch?
  let onSave: (PlanEvent) throws -> Void
  init(initial: PlanEvent, onSave: @escaping (PlanEvent) throws -> Void) {
    _event = State(initialValue: initial)
    self.onSave = onSave
  }
  private var dateBinding: Binding<Date> {
    Binding(
      get: { PlanDate.parse(event.date) ?? Date() }, set: { event.date = PlanDate.string($0) })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("일정 기록").font(.title2.weight(.semibold))
      Text("날짜와 시간, 머무를 장소를 기록하세요.").font(.system(size: 12)).foregroundStyle(Color.subtle)
      ScrollView {
        VStack(alignment: .leading, spacing: 17) {
          FieldLabel(title: "일정 이름") { TextField("어떤 순간을 계획하고 있나요?", text: $event.title) }
          HStack {
            FieldLabel(title: "날짜") {
              DatePicker(
                "", selection: dateBinding,
                in: PlanDate.parse("1900-01-01")!...PlanDate.parse("2100-12-31")!,
                displayedComponents: .date
              ).labelsHidden().environment(\.timeZone, PlanDate.calendar.timeZone).environment(
                \.locale, Locale(identifier: "ko_KR"))
            }
            FieldLabel(title: "분류") {
              Picker("", selection: $event.category) {
                ForEach(PlanCategory.allCases, id: \.self) { Text($0.label).tag($0) }
              }.labelsHidden()
            }
          }
          HStack {
            FieldLabel(title: "시작 시간 · 기본 오전 9시") { TextField("09:00", text: $event.time) }
            FieldLabel(title: "종료 시간 · 선택") { TextField("15:00", text: $event.endTime) }
          }
          HStack(alignment: .bottom) {
            FieldLabel(title: "장소") {
              TextField("서울숲 또는 도로명 주소", text: $event.place).onChange(of: event.place) { _, _ in
                invalidateLocation()
              }
            }
            Button(searching ? "검색 중…" : "장소 찾기") { search() }.disabled(
              searching || event.place.trimmingCharacters(in: .whitespaces).isEmpty
            ).buttonStyle(QuietButtonStyle())
          }
          Text("장소 검색은 Apple 지도를 사용합니다. 저장 후 네이버지도에서도 열 수 있어요.").font(.system(size: 10))
            .foregroundStyle(Color.subtle)
          if !results.isEmpty {
            VStack(spacing: 0) {
              ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                Button {
                  choose(item)
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "장소").font(.system(size: 12, weight: .medium))
                    Text(item.placemark.title ?? "").font(.system(size: 10)).foregroundStyle(
                      Color.subtle)
                  }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.buttonStyle(.plain)
                Divider()
              }
            }.background(.white, in: RoundedRectangle(cornerRadius: 8))
          }
          if let lat = event.latitude, let lng = event.longitude {
            Label(
              "위치 선택됨 · \(String(format:"%.5f, %.5f",lat,lng))",
              systemImage: "checkmark.circle.fill"
            ).font(.system(size: 11)).foregroundStyle(Color.forest)
            Text(event.address).font(.caption).foregroundStyle(Color.subtle)
            Button("위치 해제") {
              event.latitude = nil
              event.longitude = nil
              event.address = ""
            }.font(.caption)
          }
          FieldLabel(title: "메모") {
            TextEditor(text: $event.notes).frame(height: 75).overlay(
              RoundedRectangle(cornerRadius: 5).stroke(Color.line))
          }
          if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(2)
      }
      HStack {
        Spacer()
        Button("취소") {
          request?.cancel()
          dismiss()
        }.buttonStyle(QuietButtonStyle())
        Button("일정 저장") {
          do {
            if event.time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              event.time = "09:00"
            }
            let value = try event.validated()
            try onSave(value)
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
      }
    }.textFieldStyle(.roundedBorder).padding(28).frame(width: 540, height: 650).background(
      Color.paper
    ).onDisappear { request?.cancel() }
  }
  private func invalidateLocation() {
    event.latitude = nil
    event.longitude = nil
    event.address = ""
    results = []
    request?.cancel()
    searching = false
  }
  private func search() {
    let query = event.place
    request?.cancel()
    let input = MKLocalSearch.Request()
    input.naturalLanguageQuery = query
    let operation = MKLocalSearch(request: input)
    request = operation
    searching = true
    error = ""
    Task { @MainActor in
      do {
        let response = try await operation.start()
        guard request === operation else { return }
        results = Array(response.mapItems.prefix(6))
        if results.isEmpty { error = "검색 결과가 없습니다. 도로명 주소로 다시 검색해 주세요." }
      } catch { if request === operation { self.error = "장소를 찾지 못했습니다. 인터넷 연결과 주소를 확인해 주세요." } }
      if request === operation { searching = false }
    }
  }
  private func choose(_ item: MKMapItem) {
    event.latitude = item.placemark.coordinate.latitude
    event.longitude = item.placemark.coordinate.longitude
    event.address = item.placemark.title ?? ""
    results = []
    error = ""
  }
}
struct NaturalEntrySheet: View {
  @Environment(\.dismiss) var dismiss
  @State private var text = ""
  @State private var parsed: [ParsedPlan] = []
  @State private var error = ""
  let onSave: ([PlanEvent]) throws -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("문장으로 일정 추가").font(.title2.weight(.semibold))
      Text("한 줄에 하나씩, 최대 20개의 일정을 적어 주세요. 시간을 생략하면 오전 9시로 저장돼요.").font(.system(size: 12))
        .foregroundStyle(Color.subtle)
      Text("내일 오후 3시 서울숲에서 산책\n10월 3일 오후 2시부터 4시까지 성수동 카페에서 친구 만나기").font(.system(size: 11))
        .foregroundStyle(Color.subtle).textSelection(.enabled)
      TextEditor(text: $text).font(.system(size: 14)).frame(height: 100).padding(7).background(
        .white, in: RoundedRectangle(cornerRadius: 7)
      ).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.line)).onChange(of: text) { _, _ in
        parsed = []
      }
      HStack {
        Text("‘오늘·내일’은 한국 시간 기준 · 문장은 이 Mac에서 분석해요.").font(.system(size: 10)).foregroundStyle(
          Color.subtle)
        Spacer()
        Button("일정 분석") {
          do {
            parsed = try NaturalParser.parse(text)
            error = ""
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(PrimaryButtonStyle()).disabled(
          text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if !parsed.isEmpty {
        ScrollView {
          VStack(spacing: 14) {
            ForEach($parsed) { $row in
              VStack(alignment: .leading, spacing: 10) {
                Text(row.source).font(.system(size: 10)).foregroundStyle(Color.subtle).lineLimit(2)
                TextField("일정 이름", text: $row.event.title)
                HStack {
                  TextField("YYYY-MM-DD", text: $row.event.date)
                  TextField("시작 HH:mm · 기본 09:00", text: $row.event.time)
                  TextField("종료 · 선택", text: $row.event.endTime)
                }
                HStack {
                  TextField("장소 · 선택", text: $row.event.place)
                  Picker("분류", selection: $row.event.category) {
                    ForEach(PlanCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                  }.labelsHidden().frame(width: 90)
                }
                ForEach(row.warnings, id: \.self) {
                  Text($0).font(.system(size: 10)).foregroundStyle(Color(hex: 0xA2844B))
                }
              }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 9)).overlay(
                RoundedRectangle(cornerRadius: 9).stroke(Color.line))
            }
          }
        }.frame(maxHeight: 310)
        Text("장소 이름으로 저장됩니다. 지도 핀은 저장 후 일정 수정 → 장소 찾기에서 지정하세요.").font(.system(size: 10))
          .foregroundStyle(Color.subtle)
      }
      if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button("취소") { dismiss() }.buttonStyle(QuietButtonStyle())
        Button("\(parsed.count)개 일정 저장") {
          do {
            let values = try parsed.map { try $0.event.validated() }
            try onSave(values)
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.disabled(parsed.isEmpty).buttonStyle(PrimaryButtonStyle())
      }
    }.textFieldStyle(.roundedBorder).padding(28).frame(width: 650).background(Color.paper)
  }
}
