import SwiftUI

struct PlacesSettings: View {
  @Environment(\.dismiss) var dismiss
  @AppStorage("codexPlaceLookupEnabled") private var enabled = true

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("장소 정보 자동 요약").font(.title2.weight(.semibold))
      Text("이 Mac에 로그인된 Codex CLI가 공개 웹을 검색해 주차와 후기를 요약합니다.")
        .font(.system(size: 12)).foregroundStyle(Color.subtle)
      Toggle("장소 상세를 열 때 자동 조회", isOn: $enabled)
      Text("장소명과 주소만 Codex에 전달합니다. 일정 제목·날짜·메모는 전달하지 않습니다. Codex 사용량은 최초 조회 시에만 소모되며, 요약은 저장되어 같은 계정의 다른 Mac에서도 다시 사용됩니다.")
        .font(.system(size: 11)).foregroundStyle(Color.subtle)
      Text("다른 Mac에서도 Codex CLI를 설치한 뒤 ChatGPT 계정으로 로그인해야 합니다.")
        .font(.system(size: 11)).foregroundStyle(Color.subtle)
      Link("Codex CLI 설치 안내 ↗", destination: URL(string: "https://learn.chatgpt.com/docs/codex/cli")!)
        .font(.system(size: 12))
      HStack {
        Link("개인정보 처리 안내", destination: URL(string: "https://github.com/kube-guy/monthly-plan/blob/main/PRIVACY.md")!)
        Link("이용 안내", destination: URL(string: "https://github.com/kube-guy/monthly-plan/blob/main/TERMS.md")!)
        Spacer()
        Button("닫기") { dismiss() }.buttonStyle(PrimaryButtonStyle())
      }.font(.system(size: 11))
    }.padding(28).frame(width: 520).background(Color.paper)
  }
}
