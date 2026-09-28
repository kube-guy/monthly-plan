import MonthlyPlanCore
import SwiftUI

struct CalendarCard: View {
  let month: Date
  let events: [PlanEvent]
  var selected: String? = nil
  var expanded = false
  var onDay: ((String) -> Void)? = nil
  var onEvent: ((PlanEvent) -> Void)? = nil
  private var days: Int { PlanDate.calendar.range(of: .day, in: .month, for: month)!.count }
  private var offset: Int { PlanDate.calendar.component(.weekday, from: PlanDate.first(month)) - 1 }
  private var monthString: String { PlanDate.month(month) }
  private var rowHeight: CGFloat {
    expanded
      ? CGFloat(
        max(
          120,
          (Dictionary(grouping: events, by: { $0.date }).values.map(\.count).max() ?? 0) * 39 + 39))
      : 125
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        ForEach(Array("일월화수목금토".map(String.init).enumerated()), id: \.offset) { index, day in
          Text(day).font(.system(size: 11)).foregroundStyle(
            index == 0 ? Color(hex: 0xBB8580) : index == 6 ? Color(hex: 0x8199B5) : Color.subtle
          ).frame(maxWidth: .infinity)
        }
      }.padding(.vertical, 16)
      Rectangle().fill(Color.line).frame(height: 1)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0)
      {
        ForEach(0..<((offset + days + 6) / 7) * 7, id: \.self) { index in
          let day = index - offset + 1
          if day > 0 && day <= days {
            dayCell(day)
          } else {
            Color(hex: 0xFCFCF9).frame(height: rowHeight).overlay(alignment: .bottom) {
              Color.line.opacity(0.6).frame(height: 1)
            }
          }
        }
      }
      HStack(spacing: 18) {
        ForEach(PlanCategory.allCases, id: \.self) { category in
          HStack(spacing: 5) {
            Circle().fill(category.color).frame(width: 6, height: 6)
            Text(category.label).font(.system(size: 10)).foregroundStyle(Color.subtle)
          }
        }
        Spacer()
        Text("한국 시간 · KST").font(.system(size: 10)).foregroundStyle(Color.subtle)
      }.padding(18)
    }.background(.white).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(
      RoundedRectangle(cornerRadius: 12).stroke(Color.line))
  }
  private func dayCell(_ day: Int) -> some View {
    let date = String(format: "%@-%02d", monthString, day)
    let rows = events.filter { $0.date == date }
    return VStack(alignment: .leading, spacing: 5) {
      Button {
        onDay?(date)
      } label: {
        Text("\(day)").font(.system(size: 12)).foregroundStyle(
          date == PlanDate.string(Date()) ? .white : Color.ink
        ).frame(width: 26, height: 26).background(
          date == PlanDate.string(Date()) ? Color.forest : .clear, in: Circle())
      }.buttonStyle(.plain).accessibilityLabel("\(date), 일정 \(rows.count)개")
      ForEach(expanded ? rows : Array(rows.prefix(2))) { event in
        Button {
          onEvent?(event)
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(event.title).font(.system(size: 10, weight: .medium)).lineLimit(expanded ? 2 : 1)
            Text(event.time).font(.system(size: 9))
          }.frame(maxWidth: .infinity, alignment: .leading).padding(5).foregroundStyle(
            event.category.color
          ).background(event.category.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain).help(event.title)
      }
      if !expanded && rows.count > 2 {
        Button("+\(rows.count-2)개") { onDay?(date) }.font(.system(size: 9)).buttonStyle(.plain)
          .foregroundStyle(Color.subtle)
      }
      Spacer(minLength: 0)
    }.padding(.horizontal, 5).padding(.top, 7).frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: rowHeight).background(
        selected == date ? Color(hex: 0xF0F5E9) : .white
      ).overlay(alignment: .bottom) { Color.line.opacity(0.6).frame(height: 1) }.overlay(
        alignment: .trailing
      ) { Color.line.opacity(0.6).frame(width: 1) }
  }
}
struct MomentsList: View {
  let events: [PlanEvent]
  var expanded = false
  var onSelect: ((PlanEvent) -> Void)? = nil
  var body: some View {
    VStack(spacing: 0) {
      ForEach(events) { event in
        Button {
          onSelect?(event)
        } label: {
          HStack(spacing: 12) {
            VStack(spacing: 2) {
              Text("\(Int(event.date.dropFirst(5).prefix(2)) ?? 0)월").font(.system(size: 9))
                .foregroundStyle(Color.subtle)
              Text(String(Int(event.date.suffix(2)) ?? 0)).font(.system(size: 21, weight: .medium))
                .foregroundStyle(Color.forest)
            }.frame(width: 43, height: 49).background(
              Color(hex: 0xF3F5ED), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 7) {
              Text(event.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink)
                .lineLimit(expanded ? nil : 2)
              HStack(spacing: 4) {
                Image(systemName: "mappin")
                Text(event.place.isEmpty ? "장소 미정" : event.place).lineLimit(1)
                Text("· \(event.time)")
              }.font(.system(size: 10)).foregroundStyle(Color.subtle)
            }
            Spacer(minLength: 4)
            Circle().fill(event.category.color).frame(width: 6, height: 6)
          }.padding(.vertical, 13)
        }.buttonStyle(.plain)
        if event.id != events.last?.id {
          Rectangle().fill(Color.line.opacity(0.6)).frame(height: 1)
        }
      }
      if events.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "calendar.badge.plus").font(.title2)
          Text("아직 일정이 없어요.").font(.system(size: 12))
        }.foregroundStyle(Color.subtle).frame(maxWidth: .infinity).padding(.vertical, 45)
      }
    }
  }
}
