import MonthlyPlanCore
import Security
import SwiftUI

enum PlacesKeychain {
  private static let service = "io.github.kube-guy.monthly-plan", account = "google-places-api-key"
  private static var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
  static func read() throws -> String? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw PlanError.invalid("키체인에서 API 키를 읽지 못했습니다.")
    }
    return String(data: data, encoding: .utf8)
  }
  static func save(_ key: String) throws {
    let data = Data(key.utf8)
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw PlanError.invalid("API 키를 키체인에 저장하지 못했습니다.")
      }
    } else if status != errSecSuccess {
      throw PlanError.invalid("API 키를 키체인에 저장하지 못했습니다.")
    }
  }
  static func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw PlanError.invalid("API 키를 삭제하지 못했습니다.")
    }
  }
}
struct PlacesSettings: View {
  @Environment(\.dismiss) var dismiss
  @AppStorage("externalPlacesEnabled") private var enabled = false
  @State private var key = ""
  @State private var error = ""
  @State private var hasKey = false
  var body: some View {
    VStack(alignment: .leading, spacing: 19) {
      Text("외부 장소 정보 연결").font(.title2.weight(.semibold))
      Text("Google Places에서 주차 정보와 리뷰를 불러옵니다. 네이버지도 열기는 별도로 계속 사용할 수 있어요.").font(.system(size: 12))
        .foregroundStyle(Color.subtle)
      Link(
        "Google Cloud에서 Places API (New) 설정 ↗",
        destination: URL(
          string: "https://developers.google.com/maps/documentation/places/web-service/get-api-key")!
      ).font(.system(size: 12))
      FieldLabel(title: hasKey ? "API 키 · 등록됨 (변경할 때만 입력)" : "API 키") {
        SecureField("Google Places API 키", text: $key)
      }
      Toggle("장소 상세를 열 때 자동 조회", isOn: $enabled)
      Text("이 기능을 사용하면 장소명과 주소가 Google에 전송되며 API 사용 요금이 발생할 수 있습니다. 키는 이 Mac의 키체인에만 저장됩니다.").font(
        .system(size: 11)
      ).foregroundStyle(Color.subtle)
      HStack {
        Link(
          "개인정보 처리 안내",
          destination: URL(string: "https://github.com/kube-guy/monthly-plan/blob/main/PRIVACY.md")!
        )
        Link(
          "이용 안내",
          destination: URL(string: "https://github.com/kube-guy/monthly-plan/blob/main/TERMS.md")!)
      }.font(.system(size: 11))
      if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
      HStack {
        if hasKey {
          Button("연결 해제", role: .destructive) {
            do {
              try PlacesKeychain.remove()
              enabled = false
              dismiss()
            } catch { self.error = error.localizedDescription }
          }
        }
        Spacer()
        Button("닫기") { dismiss() }.buttonStyle(QuietButtonStyle())
        Button("키 저장 및 연결") {
          let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
          do {
            if !value.isEmpty {
              guard value.count >= 15 && value.count <= 300 && !value.contains(" ") else {
                throw PlanError.invalid("API 키 형식을 확인해 주세요.")
              }
              try PlacesKeychain.save(value)
            } else if !hasKey {
              throw PlanError.invalid("API 키를 입력해 주세요.")
            }
            enabled = true
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(PrimaryButtonStyle())
      }
    }.textFieldStyle(.roundedBorder).padding(28).frame(width: 520).background(Color.paper).onAppear
    {
      do { hasKey = try PlacesKeychain.read() != nil } catch {
        self.error = error.localizedDescription
      }
    }
  }
}
