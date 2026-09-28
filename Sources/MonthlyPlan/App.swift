import AppKit
import MonthlyPlanCore
import SwiftUI

@main
@MainActor
enum Launcher {
  static func main() {
    let args = CommandLine.arguments
    if args.contains("--version") {
      print("monthly-plan 0.1.0")
      return
    }
    if let index = args.firstIndex(of: "--export-demo"), args.count > index + 1 {
      _ = NSApplication.shared
      let month = PlanDate.parse("2026-09-01")!
      do {
        try ExportService.write(
          events: PlanDate.samples(month: "2026-09"), month: month, mode: .combined,
          to: URL(fileURLWithPath: args[index + 1]), isDemo: true)
        print("Exported \(args[index+1])")
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
