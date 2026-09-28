import Foundation

public struct ParsedPlan: Identifiable, Sendable {
  public var id: UUID { event.id }
  public var source: String
  public var event: PlanEvent
  public var warnings: [String]
}
private struct Match {
  var whole: String
  var groups: [String]
  subscript(_ index: Int) -> String { index == 0 ? whole : groups[index - 1] }
}
public enum NaturalParser {
  private static func matches(_ pattern: String, _ text: String) -> [Match] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { result in
      Match(
        whole: ns.substring(with: result.range),
        groups: (1..<result.numberOfRanges).map {
          result.range(at: $0).location == NSNotFound
            ? "" : ns.substring(with: result.range(at: $0))
        })
    }
  }
  private static func clean(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  private static func datePart(_ text: String, reference: Date) -> (String, String) {
    let year = PlanDate.calendar.component(.year, from: reference)
    let patterns = [
      #"(?:(\d{4})\s*년\s*)?(\d{1,2})\s*월\s*(\d{1,2})\s*일"#,
      #"\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b"#,
    ]
    for pattern in patterns {
      if let m = matches(pattern, text).first {
        let y = Int(m[1]) ?? year
        return (
          String(format: "%04d-%02d-%02d", y, Int(m[2])!, Int(m[3])!),
          text.replacingOccurrences(of: m.whole, with: " ")
        )
      }
    }
    if let m = matches(#"\b(\d{1,2})[/.](\d{1,2})(?!\d)"#, text).first {
      return (
        String(format: "%04d-%02d-%02d", year, Int(m[1])!, Int(m[2])!),
        text.replacingOccurrences(of: m.whole, with: " ")
      )
    }
    if let m = matches("오늘|내일|모레|글피", text).first {
      let days = ["오늘": 0, "내일": 1, "모레": 2, "글피": 3][m.whole]!
      return (
        PlanDate.string(PlanDate.addingDays(days, to: reference)),
        text.replacingOccurrences(of: m.whole, with: " ")
      )
    }
    if let m = matches(#"(?:(이번\s*주|다음\s*주|다다음\s*주)\s*)?([일월화수목금토])요일"#, text).first {
      let names = ["일", "월", "화", "수", "목", "금", "토"]
      let target = names.firstIndex(of: m[2])!
      let current = PlanDate.calendar.component(.weekday, from: reference) - 1
      var days = target - current
      if !m[1].isEmpty {
        let week = m[1].replacingOccurrences(of: " ", with: "")
        days =
          -((current + 6) % 7) + (target + 6) % 7 + (week == "다음주" ? 7 : week == "다다음주" ? 14 : 0)
      } else if days < 0 {
        days += 7
      }
      return (
        PlanDate.string(PlanDate.addingDays(days, to: reference)),
        text.replacingOccurrences(of: m.whole, with: " ")
      )
    }
    return ("", text)
  }
  private static let timePattern =
    #"(오전|오후|아침|저녁|밤|점심|새벽|낮)?\s*(?:(\d{1,2})\s*:\s*(\d{2})|(\d{1,2})\s*시(?:\s*(반|\d{1,2}\s*분))?)|(정오|자정)"#
  private static func clock(_ m: Match, inherited: String = "") -> (time: String, period: String) {
    if !m[6].isEmpty { return (m[6] == "정오" ? "12:00" : "00:00", m[6] == "정오" ? "오후" : "오전") }
    let h = Int(m[2].isEmpty ? m[4] : m[2]) ?? -1
    let minute =
      !m[3].isEmpty ? Int(m[3]) ?? -1 : m[5] == "반" ? 30 : Int(m[5].filter(\.isNumber)) ?? 0
    let period = m[1].isEmpty ? inherited : m[1]
    guard (0...23).contains(h), (0...59).contains(minute), m[1].isEmpty || (1...12).contains(h)
    else { return ("", period) }
    guard !(period.isEmpty && m[2].isEmpty && (1...12).contains(h)) else { return ("", period) }
    var hour = h
    if !period.isEmpty {
      if ["오후", "저녁", "밤", "낮", "점심"].contains(period) {
        if h < 12 { hour += 12 } else if h == 12 && period == "밤" { return ("", period) }
      } else if h == 12 {
        hour = 0
      }
    }
    return (String(format: "%02d:%02d", hour, minute), period)
  }
  public static func parse(_ text: String, reference: Date = Date()) throws -> [ParsedPlan] {
    let lines = text.components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty }
    guard !lines.isEmpty else { throw PlanError.invalid("일정을 한 줄 이상 적어 주세요.") }
    guard lines.count <= 20, text.count <= 12000 else {
      throw PlanError.invalid("한 번에 20개, 12,000자까지 입력할 수 있어요.")
    }
    return lines.map { source in
      var warnings: [String] = []
      let date = datePart(source, reference: reference)
      var rest = date.1
      var event = PlanEvent(date: date.0, time: "")
      if PlanDate.parse(date.0) == nil {
        event.date = ""
        warnings.append("날짜를 확인해 주세요.")
      }
      let times = matches(timePattern, rest)
      if let first = times.first {
        let start = clock(first)
        event.time = start.time
        if times.count > 1 {
          event.endTime = clock(times[1], inherited: start.period).time
          if event.endTime.isEmpty { warnings.append("종료 시간을 확인해 주세요.") }
        }
      }
      if event.time.isEmpty { warnings.append("시작 시간을 오전·오후 또는 24시간 형식으로 입력해 주세요.") }
      if times.count > 2 { warnings.append("한 줄에는 일정 하나만 입력해 주세요.") }
      if !event.endTime.isEmpty && event.endTime <= event.time {
        warnings.append("종료 시간은 같은 날의 시작보다 늦어야 해요.")
      }
      for m in times { rest = rest.replacingOccurrences(of: m.whole, with: " ") }
      rest = rest.replacingOccurrences(of: "부터", with: " ").replacingOccurrences(
        of: "까지", with: " "
      ).replacingOccurrences(of: #"[~〜–—]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      rest = clean(rest)
      let location = matches(#"(?:장소|위치)\s*[:：]\s*([^,;]+)"#, rest).first
      let title = matches(#"(?:제목|일정)\s*[:：]\s*([^,;]+)"#, rest).first
      if location != nil || title != nil {
        event.place = clean(location?[1] ?? "")
        event.title = clean(title?[1] ?? "")
      } else if let range = rest.range(of: "에서") {
        event.place = clean(String(rest[..<range.lowerBound]))
        event.title = clean(String(rest[range.upperBound...]))
      } else {
        var tokens = rest.split(separator: " ").map(String.init)
        if tokens.count >= 2 {
          event.place = tokens.removeFirst()
          event.title = tokens.joined(separator: " ")
          warnings.append("첫 단어를 장소로 추정했어요. 확인해 주세요.")
        } else {
          event.title = rest
        }
      }
      if event.title.isEmpty { warnings.append("일정 이름을 입력해 주세요.") }
      if event.place.isEmpty { warnings.append("장소 미정으로 저장됩니다.") }
      let titleText = event.title
      if matches("회의|미팅|업무|프로젝트|고객", titleText).count > 0 {
        event.category = .work
      } else if matches("전시|공연|영화|미술관|콘서트", titleText).count > 0 {
        event.category = .culture
      } else if matches("여행|휴가|공항|비행|캠핑", titleText).count > 0 {
        event.category = .trip
      }
      return ParsedPlan(source: source, event: event, warnings: warnings)
    }
  }
}
