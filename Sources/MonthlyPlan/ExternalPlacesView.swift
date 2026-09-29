import MonthlyPlanCore
import SwiftUI

private actor PlaceSummaryCache {
  static let shared = PlaceSummaryCache()
  private var entries: [String: (Date, PlaceSummary)] = [:]

  func get(_ key: String) -> PlaceSummary? {
    guard let entry = entries[key], Date().timeIntervalSince(entry.0) < 1800 else { return nil }
    return entry.1
  }

  func set(_ value: PlaceSummary, for key: String) {
    entries[key] = (Date(), value)
  }
}

struct ExternalPlacesView: View {
  let event: PlanEvent
  @AppStorage("codexPlaceLookupEnabled") private var enabled = true
  @State private var summary: PlaceSummary?
  @State private var loading = false
  @State private var error = ""
  @State private var showSettings = false
  @State private var refresh = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("주차와 후기").font(.system(size: 16, weight: .semibold))
        Spacer()
        Button { showSettings = true } label: { Image(systemName: "gearshape") }
          .buttonStyle(.plain)
      }
      if !enabled {
        Text("Codex 장소 조회가 꺼져 있습니다.")
          .font(.system(size: 12)).foregroundStyle(Color.subtle)
        Button("자동 조회 설정") { showSettings = true }.buttonStyle(QuietButtonStyle())
      } else if event.place.isEmpty {
        Text("장소 이름을 먼저 입력해 주세요.").font(.caption).foregroundStyle(Color.subtle)
      }
      if loading { ProgressView("주차와 후기를 검색하는 중…").controlSize(.small) }
      if !error.isEmpty {
        Text(error).font(.caption).foregroundStyle(.red)
        Button("다시 조회") { refresh += 1 }.font(.caption)
      }
      if let summary {
        VStack(alignment: .leading, spacing: 12) {
          Text("AI 요약 · 방문 전 확인").font(.system(size: 11)).foregroundStyle(Color.subtle)
          Label("주차 정보", systemImage: "parkingsign.circle")
            .font(.system(size: 12, weight: .semibold))
          Text(summary.parking).font(.system(size: 12)).textSelection(.enabled)
          Divider()
          Text("후기 요약").font(.system(size: 12, weight: .semibold))
          Text(summary.reviews).font(.system(size: 12)).textSelection(.enabled)
          Divider()
          Text("확인한 출처").font(.system(size: 11, weight: .semibold))
          ForEach(summary.sources) { source in
            Link(source.title + " ↗", destination: source.url)
              .font(.system(size: 11)).lineLimit(2)
          }
          Text("AI 요약은 부정확하거나 오래되었을 수 있어요. 주차 가능 여부와 요금은 방문 전 확인하세요.")
            .font(.system(size: 10)).foregroundStyle(Color.subtle)
        }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.line))
      }
      if enabled && !event.place.isEmpty && !loading {
        Button("최신 정보 다시 조회") { refresh += 1 }
          .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Color.subtle)
      }
    }.task(id: "\(event.placeKey)-\(refresh)-\(enabled)") { await load() }
      .sheet(isPresented: $showSettings, onDismiss: { refresh += 1 }) { PlacesSettings() }
  }

  @MainActor private func load() async {
    summary = nil
    error = ""
    guard enabled, !event.place.isEmpty else { return }
    loading = true
    defer { loading = false }
    do {
      if refresh == 0, let cached = await PlaceSummaryCache.shared.get(event.placeKey) {
        summary = cached
        return
      }
      let result = try await CodexPlaceClient().summary(place: event.place, address: event.address)
      try Task.checkCancellation()
      await PlaceSummaryCache.shared.set(result, for: event.placeKey)
      summary = result
    } catch is CancellationError {} catch {
      if !Task.isCancelled { self.error = error.localizedDescription }
    }
  }
}
