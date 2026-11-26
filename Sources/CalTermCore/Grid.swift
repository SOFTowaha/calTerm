import Foundation

/// The same event often syncs through several accounts; show it once.
public func deduplicated(_ events: [Event]) -> [Event] {
    struct Key: Hashable { let title: String, start: Date, end: Date, allDay: Bool }
    var result: [Event] = []
    var index: [Key: Int] = [:]
    var names: [Key: Set<String>] = [:]
    for event in events {
        let key = Key(title: event.title, start: event.start, end: event.end, allDay: event.isAllDay)
        if let i = index[key] {
            if names[key]!.insert(event.calendar).inserted { result[i].calendar += ", " + event.calendar }
            if (result[i].location ?? "").isEmpty { result[i].location = event.location }
            if result[i].link == nil { result[i].link = event.link }
        } else {
            index[key] = result.count
            names[key] = [event.calendar]
            result.append(event)
        }
    }
    return result
}

public func paint(_ text: String, _ hex: String?, _ enabled: Bool) -> String {
    guard enabled, let hex, hex.count == 6, let value = Int(hex, radix: 16) else { return text }
    return "\u{1B}[38;2;\(value >> 16);\((value >> 8) & 255);\(value & 255)m\(text)\u{1B}[0m"
}

private func columns(_ scalar: Unicode.Scalar) -> Int {
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .enclosingMark, .format: return 0
    default: break
    }
    switch scalar.value {
    case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F,
         0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1FAFF, 0x20000...0x3FFFD:
        return 2
    default:
        return 1
    }
}

public func displayWidth(_ text: String) -> Int {
    text.unicodeScalars.reduce(0) { $0 + columns($1) }
}

/// Cuts (with an ellipsis) or pads to exactly `width` terminal columns.
func fit(_ text: String, _ width: Int) -> String {
    let full = displayWidth(text)
    if full <= width { return text + String(repeating: " ", count: width - full) }
    var out = ""
    var used = 0
    for character in text {
        let w = displayWidth(String(character))
        if used + w > width - 1 { break }
        out.append(character)
        used += w
    }
    return out + "…" + String(repeating: " ", count: max(0, width - used - 1))
}

public func weekStart(containing date: Date, calendar: Calendar) -> Date {
    let day = calendar.startOfDay(for: date)
    let back = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
    return calendar.date(byAdding: .day, value: -back, to: day)!
}

/// The rows of days a month or week view shows.
public func gridWeeks(for command: Command, offset: Int, now: Date, calendar: Calendar) -> (anchor: Date, weeks: [[Date]]) {
    func add(_ component: Calendar.Component, _ value: Int, _ date: Date) -> Date {
        calendar.date(byAdding: component, value: value, to: date)!
    }
    func week(_ start: Date) -> [Date] { (0..<7).map { add(.day, $0, start) } }

    if command == .week {
        let start = add(.day, offset * 7, weekStart(containing: now, calendar: calendar))
        return (start, [week(start)])
    }
    let thisMonth = calendar.dateInterval(of: .month, for: now)!.start
    let first = add(.month, offset, thisMonth)
    let nextMonth = add(.month, 1, first)
    var start = weekStart(containing: first, calendar: calendar)
    var weeks: [[Date]] = []
    while start < nextMonth {
        weeks.append(week(start))
        start = add(.day, 7, start)
    }
    return (first, weeks)
}

func events(on day: Date, from all: [Event], calendar: Calendar) -> [Event] {
    let next = calendar.date(byAdding: .day, value: 1, to: day)!
    return sorted(all.filter { $0.start < next && ($0.end > day || $0.start >= day) })
        // All-day events first, as calendar apps do.
        .enumerated()
        .sorted { ($0.element.isAllDay ? 0 : 1, $0.offset) < ($1.element.isAllDay ? 0 : 1, $1.offset) }
        .map(\.element)
}

private struct Cell { var text: String; var color: String?; var bold = false; var inverse = false }

func wrap(_ text: String, width: Int, lines: Int) -> [String] {
    var out: [String] = []
    var current = ""
    for word in text.split(separator: " ").map(String.init) {
        let candidate = current.isEmpty ? word : current + " " + word
        if displayWidth(candidate) <= width || current.isEmpty {
            current = candidate
        } else {
            out.append(current)
            current = word
        }
    }
    if !current.isEmpty { out.append(current) }
    if out.count > lines { out = Array(out.prefix(lines - 1)) + [out[(lines - 1)...].joined(separator: " ")] }
    return out
}

/// Draws a month with one short cell per day.
public func renderGrid(_ all: [Event], anchor: Date, weeks: [[Date]], now: Date,
                       width: Int, calendar: Calendar, locale: Locale = .current,
                       color: Bool = false, icons: Bool = false) -> String {
    let cell = max(8, (width - 8) / 7)
    func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }
    let weekday = formatter("EEE")
    func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour!, parts.minute!)
    }
    func border(_ left: String, _ middle: String, _ right: String) -> String {
        paint(left + Array(repeating: String(repeating: "─", count: cell), count: 7).joined(separator: middle) + right,
              "5F87AF", color)
    }
    func row(_ cells: [Cell]) -> String {
        let bar = paint("│", "5F87AF", color)
        return bar + cells.map { c in
            var text = fit(c.text, cell)
            if color {
                if c.bold { text = "\u{1B}[1m\(text)\u{1B}[0m" }
                if c.inverse { text = "\u{1B}[7m\(text)\u{1B}[0m" } else { text = paint(text, c.color, true) }
            }
            return text
        }.joined(separator: bar) + bar
    }

    let title = formatter("MMMMyyyy").string(from: anchor)
    let total = cell * 7 + 8
    var lines = [String(repeating: " ", count: max(0, (total - displayWidth(title)) / 2)) + title,
                 border("╭", "┬", "╮"),
                 row(weeks[0].map { Cell(text: " " + weekday.string(from: $0), color: nil, bold: true) })]

    for week in weeks {
        let columnsOfCells: [[Cell]] = week.map { day in
            let isToday = calendar.isDate(day, inSameDayAs: now)
            let outside = !calendar.isDate(day, equalTo: anchor, toGranularity: .month)
            let number = String(calendar.component(.day, from: day))
            var out = [Cell(text: outside ? "" : (isToday ? " \(number) ◀ today" : " \(number)"),
                            color: nil, bold: true, inverse: isToday)]
            if outside { return out }
            let list = events(on: day, from: all, calendar: calendar)
            let room = 3
            let shown = list.count > room ? room - 1 : list.count
            for event in list.prefix(shown) {
                let time = event.isAllDay || event.start < day ? "" : clock(event.start) + " "
                let mark = icons ? icon(for: event).rawValue + " " : "•"
                out.append(Cell(text: mark + time + sanitize(event.title), color: event.color))
            }
            if list.count > shown { out.append(Cell(text: " +\(list.count - shown) more", color: nil)) }
            return out
        }
        let height = max(4, columnsOfCells.map(\.count).max()!)
        lines.append(border("├", "┼", "┤"))
        for i in 0..<height {
            lines.append(row(columnsOfCells.map { i < $0.count ? $0[i] : Cell(text: "", color: nil) }))
        }
    }
    lines.append(border("╰", "┴", "╯"))
    return lines.joined(separator: "\n")
}
