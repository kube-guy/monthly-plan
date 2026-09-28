// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "monthly-plan", platforms: [.macOS(.v14)],
  products: [.executable(name: "monthly-plan", targets: ["MonthlyPlan"])],
  targets: [
    .target(name: "MonthlyPlanCore", linkerSettings: [.linkedLibrary("sqlite3")]),
    .executableTarget(name: "MonthlyPlan", dependencies: ["MonthlyPlanCore"]),
    .executableTarget(
      name: "MonthlyPlanChecks", dependencies: ["MonthlyPlanCore"],
      path: "Tests/MonthlyPlanCoreTests"),
  ]
)
