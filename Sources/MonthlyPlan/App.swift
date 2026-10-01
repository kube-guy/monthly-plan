import AppKit
import MonthlyPlanCore
import SwiftUI

@main
@MainActor
enum Launcher {
  static func main() async {
    let args = CommandLine.arguments
    if args.contains("--version") {
      print("monthly-plan 0.1.7")
      return
    }
    if args.contains("--check-google-loopback") {
      do {
        let listener = try GoogleOAuthLoopback()
        let port = try await listener.start()
        let attempt = try GoogleOAuthAttempt(
          clientID: "123456-example.apps.googleusercontent.com", port: port)
        var callback = URLComponents(url: attempt.redirect, resolvingAgainstBaseURL: false)!
        callback.queryItems = [
          .init(name: "code", value: "LOOPBACK_CHECK"),
          .init(name: "state", value: attempt.state),
        ]
        let request = Task { try await URLSession.shared.data(from: callback.url!) }
        let received = try await listener.waitForCallback()
        guard try attempt.code(from: received) == "LOOPBACK_CHECK" else {
          throw PlanError.invalid("로컬 로그인 복귀 확인에 실패했습니다.")
        }
        _ = try await request.value
        listener.stop()
        print("Google loopback callback passed")
      } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
      }
      return
    }
    if let index = args.firstIndex(of: "--export-empty"), args.count > index + 1 {
      _ = NSApplication.shared
      let month = PlanDate.parse("2026-09-01")!
      do {
        try ExportService.write(
          events: [], month: month, mode: .combined,
          to: URL(fileURLWithPath: args[index + 1]))
        print("Exported \(args[index+1])")
      } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
      }
      return
    }
    if let index = args.firstIndex(of: "--summarize-place"), args.count > index + 2 {
      do {
        let summary = try await CodexPlaceClient().summary(
          place: args[index + 1], address: args[index + 2])
        let value: [String: Any] = [
          "parking": summary.parking, "reviews": summary.reviews,
          "sources": summary.sources.map { ["title": $0.title, "url": $0.url.absoluteString] },
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
      } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
      }
      return
    }
    MonthlyPlanApplication.main()
  }
}
struct MonthlyPlanApplication: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var store = PlanStore()
  var body: some Scene {
    WindowGroup("monthly-plan") {
      PlannerView().environmentObject(store).frame(minWidth: 1020, minHeight: 680)
        .preferredColorScheme(.light)
        .onOpenURL { url in Task { await store.handleLoginCallback(url) } }
    }
    .defaultSize(width: 1240, height: 890)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("새 일정") { NotificationCenter.default.post(name: .newPlan, object: nil) }
          .keyboardShortcut("n")
      }
    }
  }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
extension Notification.Name { static let newPlan = Notification.Name("MonthlyPlan.new") }
