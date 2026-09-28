import MonthlyPlanCore
import SwiftUI

extension Color {
  init(hex: UInt) {
    self.init(
      red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255)
  }
  static let paper = Color(hex: 0xFCFBF8), ink = Color(hex: 0x283C32),
    forest = Color(hex: 0x365F47), subtle = Color(hex: 0x899281), line = Color(hex: 0xE5E7DF)
}
extension PlanCategory { var color: Color { Color(hex: hex) } }
struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16).padding(
      .vertical, 11
    ).foregroundStyle(.white).background(
      Color.forest.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 9)
    )
  }
}
struct QuietButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 9)
      .foregroundStyle(Color.forest).background(
        configuration.isPressed ? Color.line : Color.white, in: RoundedRectangle(cornerRadius: 8)
      ).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line))
  }
}
struct Eyebrow: View {
  let title: String
  var body: some View {
    Text(title).font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Color.subtle)
  }
}
struct FieldLabel<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink)
      content
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
