import Foundation

/// Meeting links are far too long for a column; name the service instead.
public func shortLocation(_ location: String) -> String {
    location.replacing(/https?:\/\/[^\s;,]+/) { match -> String in
        let host = URL(string: String(match.0))?.host()?.lowercased() ?? ""
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if on("teams.microsoft.com") || on("teams.live.com") { return "Teams link" }
        if on("zoom.us") { return "Zoom link" }
        if on("meet.google.com") { return "Google Meet link" }
        return host.isEmpty ? "link" : host
    }
}

private let palette = ["5FD7FF", "FF87AF", "87D787", "FFAF5F", "AF87FF", "FFD75F", "5FD7AF"]

/// One thin rounded table per day, each with its own border colour.
public func renderTable(_ all: [Event], days: [Date], now: Date, width: Int, calendar: Calendar,
                        locale: Locale = .current, color: Bool = false, icons: Bool = false) -> String {
    let total = min(max(width, 64), 150)
    // Four columns: five borders plus a space either side of each cell.
    let room = total - 13
    let timeWidth = 13
    let calendarWidth = max(10, min(22, room / 6))
    let rest = room - timeWidth - calendarWidth
    let whereWidth = rest * 2 / 5
    let widths = [timeWidth, rest - whereWidth, whereWidth, calendarWidth]

    let heading = DateFormatter()
    heading.calendar = calendar
    heading.timeZone = calendar.timeZone
    heading.locale = locale
    heading.setLocalizedDateFormatFromTemplate("EEEEMMMMdyyyy")

    func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour!
        return String(format: "%d:%02d", (hour + 11) % 12 + 1, parts.minute!) + (hour < 12 ? "a" : "p")
    }

    var tables: [String] = []
    for day in days {
        let list = events(on: day, from: all, calendar: calendar)
        if list.isEmpty { continue }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let accent = palette[(calendar.component(.weekday, from: day) - 1) % palette.count]
        let bar = paint("│", accent, color)
        func rule(_ left: String, _ joint: String, _ right: String) -> String {
            paint(left + widths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: joint) + right,
                  accent, color)
        }
        func row(_ cells: [String], hex: String?, bold: Bool = false) -> String {
            bar + zip(cells, widths).enumerated().map { index, pair in
                var text = fit(pair.0, pair.1)
                if color && bold { text = "\u{1B}[1m\(text)\u{1B}[0m" }
                // Only the event title takes the calendar's colour, so text stays readable.
                else if index == 1 { text = paint(text, hex, color) }
                return " \(text) "
            }.joined(separator: bar) + bar
        }

        var title = (icons ? "\u{F073}  " : "") + heading.string(from: day)
        if calendar.isDate(day, inSameDayAs: now) { title += "  (today)" }
        var lines = [
            paint("╭" + String(repeating: "─", count: total - 2) + "╮", accent, color),
            bar + " " + (color ? "\u{1B}[1m\(fit(title, total - 4))\u{1B}[0m" : fit(title, total - 4)) + " " + bar,
            rule("├", "┬", "┤"),
            row(["Time", "Event", "Where", "Calendar"], hex: nil, bold: true),
        ]
        for event in list {
            let time: String
            if event.isAllDay { time = "all day" }
            else if event.start < day { time = event.end > nextDay ? "all day" : "until " + clock(event.end) }
            else if event.end > nextDay { time = clock(event.start) + " →" }
            else { time = clock(event.start) + "–" + clock(event.end) }

            let columns = [
                [time],
                wrap((icons ? icon(for: event).rawValue + " " : "") + sanitize(event.title), width: widths[1], lines: 3),
                wrap(shortLocation(sanitize(event.location ?? "")), width: widths[2], lines: 2),
                wrap(sanitize(event.calendar), width: widths[3], lines: 2),
            ]
            lines.append(rule("├", "┼", "┤"))
            for i in 0..<max(1, columns.map(\.count).max()!) {
                lines.append(row(columns.map { i < $0.count ? $0[i] : "" }, hex: event.color))
            }
        }
        lines.append(rule("╰", "┴", "╯"))
        tables.append(lines.joined(separator: "\n"))
    }
    return tables.isEmpty ? "No events." : tables.joined(separator: "\n")
}
