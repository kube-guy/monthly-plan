import Foundation
import MonthlyPlanCore
import Security

enum CloudCredentials {
  private static func query(_ project: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "io.github.kube-guy.monthly-plan",
      kSecAttrAccount as String: "supabase-session-" + project,
    ]
  }
  static func read(_ project: String) throws -> SupabaseSession? {
    var item = query(project)
    item[kSecReturnData as String] = true
    item[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(item as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw PlanError.invalid("로그인 정보를 키체인에서 읽지 못했습니다.")
    }
    return try JSONDecoder().decode(SupabaseSession.self, from: data)
  }
  static func save(_ session: SupabaseSession, project: String) throws {
    let data = try JSONEncoder().encode(session)
    let status = SecItemUpdate(
      query(project) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query(project)
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw PlanError.invalid("로그인 정보를 키체인에 저장하지 못했습니다.")
      }
    } else if status != errSecSuccess {
      throw PlanError.invalid("로그인 정보를 키체인에 저장하지 못했습니다.")
    }
  }
  static func remove(_ project: String) throws {
    let status = SecItemDelete(query(project) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw PlanError.invalid("키체인의 로그인 정보를 삭제하지 못했습니다.")
    }
  }
}
