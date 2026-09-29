import MonthlyPlanCore
import SwiftUI

struct CloudSettings: View {
  @EnvironmentObject var store: PlanStore
  @Environment(\.dismiss) private var dismiss
  @State private var projectURL = ""
  @State private var key = ""
  @State private var email = ""
  @State private var code = ""
  @State private var sentTo: String?
  @State private var notice = ""
  @State private var failure = ""
  @State private var confirmImport = false
  @State private var confirmLogout = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 19) {
        HStack {
          Label("내 모든 Mac에서 같은 일정", systemImage: "icloud").font(.title2.weight(.semibold))
          Spacer()
          Button("닫기") { dismiss() }.buttonStyle(QuietButtonStyle())
        }
        Text("Supabase에 로그인하면 일정과 장소 연결이 동기화됩니다. 인터넷이 끊겨도 변경은 이 Mac에 남고, 다시 연결되면 전송됩니다.")
          .font(.system(size: 12)).foregroundStyle(Color.subtle)
        if store.signedIn {
          Label(store.accountEmail ?? "로그인됨", systemImage: "person.crop.circle").textSelection(
            .enabled)
          Text(store.configuration?.url.host ?? "").font(.caption).foregroundStyle(Color.subtle)
          Text(store.syncStatus).font(.system(size: 12)).textSelection(.enabled)
          if let last = store.lastSync {
            Text("최근 완료: \(last.formatted(date: .omitted, time: .shortened))").font(.caption)
          }
          HStack {
            Button("지금 동기화") { Task { await store.sync() } }.buttonStyle(PrimaryButtonStyle())
            if store.syncBusy { ProgressView().controlSize(.small) }
            Spacer()
            Button("로그아웃") { confirmLogout = true }
          }.disabled(store.busy)
          Divider()
          Text("기존 일정 가져오기").font(.headline)
          Text(
            "로그인 전에 이 Mac에서 작성한 일정을 현재 계정으로 복사합니다. 다른 계정의 일정은 가져오지 않습니다. 다시 가져오면 중복 일정이 생길 수 있어요."
          )
          .font(.caption).foregroundStyle(Color.subtle)
          Button("이 Mac의 기존 일정 가져오기") { confirmImport = true }.disabled(store.busy)
          if !store.conflicts.isEmpty {
            Divider()
            Text("두 Mac에서 수정한 일정").font(.headline)
            Text("두 내용 중 보관할 것을 선택해 주세요. 삭제도 하나의 변경으로 표시됩니다.").font(.caption)
            ForEach(store.conflicts) { conflict in
              VStack(alignment: .leading, spacing: 10) {
                Text(conflict.title).font(.headline)
                Text("이 Mac: \(description(conflict.local.value, deleted: conflict.local.deleted))")
                  .textSelection(.enabled)
                Text("온라인: \(description(conflict.remote.value, deleted: conflict.remote.deleted))")
                  .textSelection(.enabled)
                HStack {
                  Button("이 Mac 내용 유지") { resolve(conflict, keepLocal: true) }
                  Button("온라인 내용 사용") { resolve(conflict, keepLocal: false) }
                }.disabled(store.busy)
              }.font(.caption).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
            }
          }
        } else {
          FieldLabel(title: "Supabase 프로젝트 URL") {
            TextField("https://프로젝트주소.supabase.co", text: $projectURL)
          }
          FieldLabel(title: "Publishable key 또는 anon key") {
            SecureField("프로젝트의 공개 API 키", text: $key)
          }
          Text("이 두 설정은 다른 Mac에도 동일하게 입력합니다. secret·service_role 키는 사용하지 않습니다.")
            .font(.caption).foregroundStyle(Color.subtle)
          Button("프로젝트 연결") {
            do {
              try store.configure(url: projectURL, key: key)
              sentTo = nil
              code = ""
              notice = "프로젝트 설정을 저장했습니다. 이메일로 로그인해 주세요."
              failure = ""
            } catch { failure = error.localizedDescription }
          }.disabled(store.busy)
          Divider()
          FieldLabel(title: "로그인 이메일") { TextField("이메일 주소", text: $email) }
          Button("로그인 메일 받기") {
            Task {
              do {
                let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
                try await store.sendCode(email: address)
                sentTo = address
                code = ""
                notice = "새 메일의 로그인 링크를 이 Mac에서 열면 앱으로 돌아와 로그인됩니다. 앱은 열린 상태로 두세요."
                failure = ""
              } catch { failure = error.localizedDescription }
            }
          }.disabled(store.busy || store.configuration == nil)
          if let sentTo {
            Text("메일을 보낸 주소: \(sentTo)").font(.caption)
            FieldLabel(title: "앱이 열리지 않을 때 · 링크 또는 인증번호") {
              SecureField("메일의 링크를 복사해 붙여 넣기", text: $code)
            }
            Button("로그인 및 동기화") {
              Task {
                do {
                  try await store.login(
                    email: sentTo, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
                  code = ""
                  notice = ""
                  failure = ""
                } catch { failure = error.localizedDescription }
              }
            }.buttonStyle(PrimaryButtonStyle()).disabled(store.busy)
          }
          if store.authBusy { ProgressView().controlSize(.small) }
          Link(
            "처음 연결하는 경우 · Supabase 설정 안내 ↗",
            destination: URL(
              string: "https://github.com/kube-guy/monthly-plan/blob/main/docs/SUPABASE.md")!
          )
          .font(.caption)
        }
        if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(Color.forest) }
        if !failure.isEmpty { Text(failure).font(.caption).foregroundStyle(.red) }
        if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
      }.padding(28)
    }.textFieldStyle(.roundedBorder).frame(width: 600, height: 700).background(Color.paper)
      .onAppear {
        projectURL = store.configuration?.url.absoluteString ?? ""
        key = store.configuration?.publishableKey ?? ""
      }
      .confirmationDialog(
        "기존 일정을 현재 계정에 복사할까요?", isPresented: $confirmImport, titleVisibility: .visible
      ) {
        Button("복사하고 동기화") {
          do {
            try store.importLocalEvents()
            notice = "기존 일정을 복사했습니다."
            failure = ""
          } catch { failure = error.localizedDescription }
        }
      } message: {
        Text("현재 계정의 Supabase 저장소로 전송됩니다. 원본은 이 Mac에 그대로 남습니다.")
      }
      .confirmationDialog(
        "이 Mac에서 로그아웃할까요?", isPresented: $confirmLogout, titleVisibility: .visible
      ) {
        Button("로그아웃") {
          Task {
            do {
              try await store.logout()
              notice = "로그아웃했습니다."
              failure = ""
            } catch { failure = error.localizedDescription }
          }
        }
      } message: {
        Text(
          "전송 대기 \(store.pendingCount)개. 아직 전송하지 않은 변경과 계정별 저장 파일은 이 Mac에 남으며, 같은 계정으로 다시 로그인하면 이어서 동기화합니다."
        )
      }
  }
  private func description(_ value: SyncValue?, deleted: Bool) -> String {
    if deleted { return "삭제됨" }
    if let event = value?.event {
      return
        "\(event.title) · \(event.date) \(event.time)\(event.endTime.isEmpty ? "" : "–" + event.endTime) · \(event.place) \(event.address) · \(event.category.label)\n\(event.notes)"
    }
    return value?.googlePlaceID ?? "장소 연결 해제"
  }
  private func resolve(_ conflict: SyncConflict, keepLocal: Bool) {
    do {
      try store.resolve(conflict, keepLocal: keepLocal)
      failure = ""
    } catch { failure = error.localizedDescription }
  }
}
