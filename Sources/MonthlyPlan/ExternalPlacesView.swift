import MonthlyPlanCore
import SwiftUI

struct ExternalPlacesView: View {
  let event: PlanEvent
  @EnvironmentObject var store: PlanStore
  @AppStorage("externalPlacesEnabled") private var enabled = false
  @State private var details: GooglePlace?
  @State private var candidates: [GooglePlace] = []
  @State private var loading = false
  @State private var error = ""
  @State private var showSettings = false
  @State private var refresh = 0
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("주차와 후기").font(.system(size: 16, weight: .semibold))
        Spacer()
        Button {
          showSettings = true
        } label: {
          Image(systemName: "gearshape")
        }.buttonStyle(.plain)
      }
      if !enabled {
        Text("외부 정보를 자동으로 가져오려면 Google Places를 연결하세요.").font(.system(size: 12)).foregroundStyle(
          Color.subtle)
        Button("외부 정보 연결") { showSettings = true }.buttonStyle(QuietButtonStyle())
      } else if event.place.isEmpty {
        Text("장소 이름을 먼저 입력해 주세요.").font(.caption).foregroundStyle(Color.subtle)
      }
      if loading { ProgressView("장소 정보를 불러오는 중…").controlSize(.small) }
      if !error.isEmpty {
        Text(error).font(.caption).foregroundStyle(.red)
        Button("다시 조회") { refresh += 1 }.font(.caption)
      }
      if !candidates.isEmpty {
        Text("이 장소가 맞나요? 처음 한 번 확인하면 다음부터 자동 조회해요.").font(.system(size: 11)).foregroundStyle(
          Color.subtle)
        ForEach(candidates) { place in
          Button {
            do {
              try store.linkExternalPlace(id: place.id, to: event)
              candidates = []
              refresh += 1
            } catch { self.error = error.localizedDescription }
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(place.displayName?.text ?? "장소").font(.system(size: 12, weight: .medium))
              Text(place.formattedAddress ?? "").font(.system(size: 10)).foregroundStyle(
                Color.subtle)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(
              .white, in: RoundedRectangle(cornerRadius: 7))
          }.buttonStyle(.plain)
        }
        GoogleAttribution()
      }
      if let place = details {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text(place.displayName?.text ?? event.place).font(.system(size: 13, weight: .semibold))
            Spacer()
            if let rating = place.rating {
              Text(String(format: "★ %.1f", rating)).font(.system(size: 12)).foregroundStyle(
                Color(hex: 0xA78035))
            }
          }
          if let count = place.userRatingCount {
            Text("Google 평점 · 리뷰 \(count)개 기준").font(.system(size: 10)).foregroundStyle(
              Color.subtle)
          }
          Label("주차 정보", systemImage: "parkingsign.circle").font(
            .system(size: 12, weight: .semibold))
          if place.parkingLines.isEmpty {
            Text("제공된 주차 정보가 없습니다. 방문 전 장소에 확인해 주세요.").font(.system(size: 12)).foregroundStyle(
              Color.subtle)
          } else {
            ForEach(place.parkingLines, id: \.self) { Text($0).font(.system(size: 12)) }
            Text("요금·만차 여부는 제공되지 않아요.").font(.system(size: 10)).foregroundStyle(Color.subtle)
          }
          Divider()
          Text("방문자 후기").font(.system(size: 12, weight: .semibold))
          Text("Google이 제공한 관련성 순 리뷰 중 최대 3개입니다.").font(.system(size: 10)).foregroundStyle(
            Color.subtle)
          if (place.reviews ?? []).isEmpty {
            Text("제공된 후기가 없습니다.").font(.system(size: 12)).foregroundStyle(Color.subtle)
          }
          ForEach(Array((place.reviews ?? []).prefix(3))) { review in ReviewCard(review: review) }
          if let url = safeWebURL(place.googleMapsUri) {
            Link("Google Maps에서 전체 정보 보기 ↗", destination: url).font(.system(size: 11))
          }
          ForEach(Array((place.attributions ?? []).enumerated()), id: \.offset) { _, attribution in
            if let url = safeWebURL(attribution.providerUri) {
              Link(attribution.provider ?? "데이터 제공자", destination: url).font(.system(size: 10))
            } else if let provider = attribution.provider {
              Text(provider).font(.system(size: 10))
            }
          }
          GoogleAttribution()
        }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 9)).overlay(
          RoundedRectangle(cornerRadius: 9).stroke(Color.line))
      }
      if enabled && !event.place.isEmpty && !loading {
        Button("연결된 장소 다시 선택") {
          do {
            try store.unlinkExternalPlace(for: event)
            details = nil
            refresh += 1
          } catch { self.error = error.localizedDescription }
        }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Color.subtle)
      }
    }.task(id: "\(event.placeKey)-\(refresh)-\(enabled)") { await load() }.sheet(
      isPresented: $showSettings, onDismiss: { refresh += 1 }
    ) { PlacesSettings() }
  }
  @MainActor private func load() async {
    details = nil
    candidates = []
    error = ""
    guard enabled, !event.place.isEmpty else { return }
    loading = true
    defer { loading = false }
    do {
      guard let key = try PlacesKeychain.read(), !key.isEmpty else {
        throw PlanError.invalid("앱 설정에서 Google Places API 키를 등록해 주세요.")
      }
      let client = PlacesClient(key: key)
      if let id = try store.externalPlaceID(for: event) {
        let value = try await client.details(id: id)
        try Task.checkCancellation()
        details = value
      } else {
        let values = try await client.search(place: event.place, address: event.address)
        try Task.checkCancellation()
        candidates = values
        if values.isEmpty { error = "일치하는 장소를 찾지 못했습니다. 일정의 장소명과 주소를 확인해 주세요." }
      }
    } catch is CancellationError {} catch {
      if !Task.isCancelled { self.error = error.localizedDescription }
    }
  }
}
private func safeWebURL(_ text: String?) -> URL? {
  guard let text, let url = URL(string: text),
    ["https", "http"].contains(url.scheme?.lowercased() ?? "")
  else { return nil }
  return url
}
struct GoogleAttribution: View {
  var body: some View {
    HStack {
      Text("Google Maps").font(.system(size: 12, weight: .regular)).foregroundStyle(
        Color(hex: 0x5E5E5E))
      Spacer()
      Link(
        "리뷰 정책",
        destination: URL(string: "https://support.google.com/contributionpolicy/answer/7400114")!
      ).font(.system(size: 10))
    }.padding(.top, 6)
  }
}
struct ReviewCard: View {
  let review: PlaceReview
  @State private var expanded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        if let url = safeWebURL(review.authorAttribution?.photoUri) {
          AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
          } placeholder: {
            Circle().fill(Color.line)
          }.frame(width: 28, height: 28).clipShape(Circle())
        }
        if let url = safeWebURL(review.authorAttribution?.uri) {
          Link(review.authorAttribution?.displayName ?? "작성자", destination: url).font(
            .system(size: 11, weight: .medium))
        } else {
          Text(review.authorAttribution?.displayName ?? "작성자").font(
            .system(size: 11, weight: .medium))
        }
        Spacer()
        if let rating = review.rating {
          Text(String(format: "★ %.0f", rating)).font(.system(size: 10))
        }
      }
      if let text = review.text?.text {
        Text(text).font(.system(size: 12)).lineSpacing(3).lineLimit(expanded ? nil : 3)
        if text.count > 80 {
          Button(expanded ? "접기" : "후기 더 보기") { expanded.toggle() }.font(.system(size: 10))
            .buttonStyle(.plain).foregroundStyle(Color.forest)
        }
      }
      HStack {
        Text(review.relativePublishTimeDescription ?? "")
        if let visit = review.visitDate, let year = visit.year, let month = visit.month {
          Text("방문 \(year)년 \(month)월")
        }
        Spacer()
        if let url = safeWebURL(review.googleMapsUri) { Link("원문 보기 ↗", destination: url) }
      }.font(.system(size: 9)).foregroundStyle(Color.subtle)
      if review.text?.languageCode != review.originalText?.languageCode, review.originalText != nil
      {
        Text("번역된 후기일 수 있어요. 원문에서 확인하세요.").font(.system(size: 9)).foregroundStyle(Color.subtle)
      }
    }.padding(.vertical, 10).overlay(alignment: .bottom) {
      Color.line.opacity(0.6).frame(height: 1)
    }
  }
}
