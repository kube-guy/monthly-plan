import AppKit
import MonthlyPlanCore
import SwiftUI
import UniformTypeIdentifiers

enum ExportMode: String, CaseIterable, Identifiable {
  case combined, calendar, moments
  var id: String { rawValue }
  var label: String {
    switch self {
    case .combined: "달력 + 이달의 순간들"
    case .calendar: "달력만"
    case .moments: "이달의 순간들만"
    }
  }
}
struct ExportBoard: View {
  let events: [PlanEvent]
  let month: Date
  let mode: ExportMode
  let isDemo: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 12) {
          Eyebrow(title: "MONTHLY PLAN")
          Text(PlanDate.month(month).replacingOccurrences(of: "-", with: ".")).font(
            .system(size: 38, weight: .medium)
          ).foregroundStyle(Color.ink)
          Text("기억하고 싶은, 이달의 순간들").font(.system(size: 13)).foregroundStyle(Color.subtle)
        }
        Spacer()
        if isDemo { Text("둘러보기 · 예시 일정").font(.system(size: 12)).foregroundStyle(Color.subtle) }
      }
      HStack(alignment: .top, spacing: 24) {
        if mode != .moments {
          CalendarCard(month: month, events: events, expanded: true).frame(
            width: mode == .combined ? 900 : 1080)
        }
        if mode != .calendar {
          VStack(alignment: .leading, spacing: 14) {
            Text("이달의 순간들 · \(events.count)").font(.system(size: 18, weight: .semibold))
              .foregroundStyle(Color.ink)
            MomentsList(events: events, expanded: true)
          }.padding(24).frame(width: mode == .combined ? 380 : 600).background(
            .white, in: RoundedRectangle(cornerRadius: 12)
          ).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line))
        }
      }
      HStack {
        Text("monthly-plan")
        Spacer()
        Text("한국 시간 · KST")
      }.font(.system(size: 10)).foregroundStyle(Color.subtle)
    }.padding(40).background(Color.paper).environment(\.colorScheme, .light)
  }
}
@MainActor
enum ExportService {
  static func write(
    events: [PlanEvent], month: Date, mode: ExportMode, to url: URL, isDemo: Bool = false
  ) throws {
    let board = ExportBoard(
      events: PlanDate.sorted(events), month: month, mode: mode, isDemo: isDemo)
    let size = NSHostingView(rootView: board).fittingSize
    guard size.width.isFinite, size.height.isFinite, size.width <= 8000, size.height <= 8000 else {
      throw PlanError.invalid("이미지가 너무 큽니다. 달력과 목록을 각각 내보내 주세요.")
    }
    let renderer = ImageRenderer(content: board)
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.cgImage else { throw PlanError.invalid("이미지를 만들지 못했습니다.") }
    guard image.width <= 16000, image.height <= 16000 else {
      throw PlanError.invalid("이미지가 너무 큽니다. 달력과 목록을 각각 내보내 주세요.")
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    let jpg = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
    guard
      let data = bitmap.representation(
        using: jpg ? .jpeg : .png, properties: jpg ? [.compressionFactor: 0.92] : [:])
    else { throw PlanError.invalid("이미지 파일을 만들지 못했습니다.") }
    try data.write(to: url, options: .atomic)
  }
  static func chooseAndWrite(
    events: [PlanEvent], month: Date, mode: ExportMode, format: String, isDemo: Bool
  ) throws -> Bool {
    let panel = NSSavePanel()
    panel.title = "이달의 일정을 이미지로 저장"
    panel.allowedContentTypes = format == "png" ? [.png] : [.jpeg]
    panel.nameFieldStringValue = "monthly-plan-\(PlanDate.month(month))-\(mode.rawValue).\(format)"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return false }
    try write(events: events, month: month, mode: mode, to: url, isDemo: isDemo)
    return true
  }
}
struct ExportSheet: View {
  let events: [PlanEvent]
  let month: Date
  let isDemo: Bool
  @Environment(\.dismiss) var dismiss
  @State private var mode: ExportMode = .combined
  @State private var format = "png"
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("이미지로 내보내기").font(.title2.weight(.semibold))
      Text("선택한 날짜와 관계없이 이달 전체를 저장합니다. 지도는 이미지에 포함되지 않아요.").font(.system(size: 12)).foregroundStyle(
        Color.subtle)
      Picker("내보낼 내용", selection: $mode) { ForEach(ExportMode.allCases) { Text($0.label).tag($0) } }
      Picker("파일 형식", selection: $format) {
        Text("PNG · 선명한 원본").tag("png")
        Text("JPG · 작은 파일").tag("jpg")
      }
      if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Spacer()
        Button("취소") { dismiss() }.buttonStyle(QuietButtonStyle())
        Button("저장 위치 선택") {
          do {
            if try ExportService.chooseAndWrite(
              events: events, month: month, mode: mode, format: format, isDemo: isDemo)
            {
              dismiss()
            }
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(PrimaryButtonStyle())
      }
    }.padding(30).frame(width: 500).background(Color.paper)
  }
}
