import Foundation

/// Text with a style, laid out by terminal columns before colour is added.
struct Span {
    var text: String
    var hex: String? = nil
    var bold = false
    var inverse = false
    var dim = false
    var underline = false
    var background: String? = nil
}

func draw(_ spans: [Span], width: Int, color: Bool) -> String {
    var out = ""
    var used = 0
    for span in spans where used < width {
        let w = min(displayWidth(span.text), width - used)
        var text = fit(span.text, w)
        used += w
        if color {
            var codes: [String] = []
            if span.bold { codes.append("1") }
            if span.dim { codes.append("2") }
            if span.underline { codes.append("4") }
            if span.inverse { codes.append("7") }
            if let hex = span.hex, let v = Int(hex, radix: 16) {
                codes.append("38;2;\(v >> 16);\((v >> 8) & 255);\(v & 255)")
            }
            if let hex = span.background, let v = Int(hex, radix: 16) {
                codes.append("48;2;\(v >> 16);\((v >> 8) & 255);\(v & 255)")
            }
            if !codes.isEmpty { text = "\u{1B}[\(codes.joined(separator: ";"))m\(text)\u{1B}[0m" }
        }
        out += text
    }
    return out + String(repeating: " ", count: width - used)
}

/// A rounded panel of exactly `width` by `height`.
private func panel(_ title: String, _ rows: [[Span]], width: Int, height: Int,
                   accent: String, color: Bool) -> [String] {
    let edge = { (text: String) in paint(text, accent, color) }
    let label = fit(" \(title) ", min(displayWidth(title) + 2, width - 4))
    var lines = [edge("╭─") + (color ? "\u{1B}[1m\(label)\u{1B}[0m" : label)
                 + edge(String(repeating: "─", count: width - 3 - displayWidth(label)) + "╮")]
    for i in 0..<(height - 2) {
        let row = i < rows.count ? rows[i] : []
        lines.append(edge("│") + " " + draw(row, width: width - 4, color: color) + " " + edge("│"))
    }
    lines.append(edge("╰" + String(repeating: "─", count: width - 2) + "╯"))
    return lines
}

func clockText(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    let hour = parts.hour!
    return String(format: "%d:%02d", (hour + 11) % 12 + 1, parts.minute!) + (hour < 12 ? "a" : "p")
}

extension App {
    public static let minimumSize = (width: 72, height: 22)

    /// The whole screen as `height` lines, each `width` columns wide.
    public func frame(width: Int, height: Int, locale: Locale = .current, color: Bool = true) -> [String] {
        if width < Self.minimumSize.width || height < Self.minimumSize.height {
            return ["Enlarge the window to at least 72×22.", "Press q to quit."]
        }
        func formatted(_ template: String, _ date: Date) -> String {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = locale
            f.setLocalizedDateFormatFromTemplate(template)
            return f.string(from: date)
        }
        func when(_ event: Event, on day: Date) -> String {
            let end = calendar.date(byAdding: .day, value: 1, to: day)!
            if event.isAllDay || (event.start < day && event.end > end) { return "all day" }
            if event.start < day { return "until " + clockText(event.end, calendar: calendar) }
            if event.end > end { return clockText(event.start, calendar: calendar) + " →" }
            return clockText(event.start, calendar: calendar) + "–" + clockText(event.end, calendar: calendar)
        }

        // Header: what is coming up next.
        // An icon followed by space, or nothing when icons are off.
        func glyph(_ code: String) -> String { icons ? code + "  " : "" }
        var header = [Span(text: " " + glyph("\u{F073}") + "calTerm ", bold: true, inverse: true)]
        if let next = nextEvent(in: events, now: now) {
            let minutes = Int(next.start.timeIntervalSince(now) / 60)
            let until = next.start <= now ? "now"
                : minutes < 60 ? "in \(max(minutes, 1))m"
                : minutes < 1440 ? "in \(minutes / 60)h \(minutes % 60)m"
                : "in \(minutes / 1440)d"
            header += [Span(text: "  " + glyph("\u{F017}") + "Next \(until): ", hex: "FFD75F"), Span(text: next.title, bold: true)]
        }

        let bodyHeight = height - 2
        let leftWidth = 33
        let rightWidth = width - leftWidth

        // Left: mini month, then the calendars in use.
        let month = gridWeeks(for: .month, offset: 0, now: day, calendar: calendar)
        var mini: [[Span]] = [month.weeks[0].map {
            Span(text: " " + String(formatted("EEEEEE", $0).prefix(2)) + " ", dim: true)
        }]
        for week in month.weeks {
            mini.append(week.map { date in
                guard calendar.isDate(date, equalTo: month.anchor, toGranularity: .month) else {
                    return Span(text: "    ")
                }
                let busy = !CalTermCore.events(on: date, from: events, calendar: calendar).isEmpty
                let isToday = calendar.isDate(date, inSameDayAs: now)
                let number = String(format: "%2d", calendar.component(.day, from: date))
                return Span(text: " " + number + (busy ? "•" : " "), hex: isToday ? "FF87AF" : nil,
                            bold: isToday || busy, inverse: date == day, underline: isToday)
            })
        }
        let miniHeight = mini.count + 2
        var legend: [[Span]] = []
        var seen: Set<String> = []
        for event in sorted(events) where seen.insert(event.calendar).inserted {
            legend.append([Span(text: "● ", hex: event.color), Span(text: event.calendar)])
        }
        let left = panel(formatted("MMMMyyyy", day), mini, width: leftWidth, height: miniHeight,
                         accent: "5FD7FF", color: color)
            + panel("Calendars", legend, width: leftWidth, height: bodyHeight - miniHeight,
                    accent: "5F87AF", color: color)

        // Right: the day's agenda (or search results), then the selected event.
        let detailHeight = 8
        let listHeight = bodyHeight - detailHeight
        let searching = mode == .results
        let list = searching ? results : agenda
        let room = listHeight - 2
        let first = max(0, min(selected - room / 2, list.count - room))
        var rows: [[Span]] = list.enumerated().dropFirst(first).prefix(room).map { index, event in
            let shownDay = searching ? calendar.startOfDay(for: event.start) : day
            var spans = [Span(text: index == selected ? "▌" : " ", hex: "FFD75F"), Span(text: icons ? icon(for: event).rawValue + "  " : "● ", hex: event.color)]
            if searching { spans.append(Span(text: fit(formatted("MMMd", event.start), 8), dim: true)) }
            spans.append(Span(text: fit(when(event, on: shownDay), 15), dim: event.end <= now))
            spans.append(Span(text: event.title, bold: index == selected, dim: event.end <= now))
            return spans
        }
        if rows.isEmpty { rows = [[Span(text: "Nothing scheduled.", dim: true)]] }
        let heading = searching
            ? "\(results.count) match\(results.count == 1 ? "" : "es") for “\(input)”"
            : formatted("EEEEMMMMd", day) + (calendar.isDate(day, inSameDayAs: now) ? " · today" : "")

        var detail: [[Span]] = []
        if list.indices.contains(selected) {
            let event = list[selected]
            let inner = rightWidth - 7
            detail = wrap((icons ? icon(for: event).rawValue + " " : "") + event.title, width: inner + 3, lines: 2).map { [Span(text: $0, hex: event.color, bold: true)] }
            detail.append([Span(text: glyph("\u{F017}") + formatted("EEEMMMd", event.start) + " · "
                                + when(event, on: calendar.startOfDay(for: event.start)))])
            if let location = event.location, !location.isEmpty {
                detail.append([Span(text: glyph("\u{F041}") + shortLocation(location))])
            }
            detail.append([Span(text: glyph("\u{F073}") + event.calendar)])
            if let link = event.link {
                detail.append([Span(text: glyph("\u{F0C1}") + "press o to open \(URL(string: link)?.host() ?? "link")", hex: "5FD7FF")])
            }
        }
        var right = panel(heading, rows, width: rightWidth, height: listHeight, accent: "FF87AF", color: color)
            + panel("Details", detail, width: rightWidth, height: detailHeight, accent: "87D787", color: color)

        if mode == .help {
            let keys = [("← → / h l", "previous / next day"), ("↑ ↓ / k j", "previous / next week"),
                        ("p  n", "previous / next month"), ("t", "today"), ("Tab / Shift+Tab", "select event"),
                        ("o / Enter", "open the event's link"), ("g", "go to a date (“next friday”)"),
                        ("/", "search events"), ("r", "refresh"), ("q", "quit")]
            right = panel("Keys (any key closes)", keys.map { [Span(text: fit($0.0, 18), bold: true), Span(text: $0.1)] },
                          width: rightWidth, height: bodyHeight, accent: "FFD75F", color: color)
        }

        let footer: [Span]
        switch mode {
        case .goto: footer = [Span(text: " Go to: ", bold: true), Span(text: input + "▏")]
        case .search: footer = [Span(text: " Search: ", bold: true), Span(text: input + "▏")]
        case .results: footer = [Span(text: " ↑↓ choose · Enter jump · Esc back", dim: true)]
        default:
            footer = message.isEmpty
                ? [Span(text: " ? help  q quit  ←→ day  ↑↓ week  p/n month  t today  Tab event  o open  g goto  / search", dim: true)]
                : [Span(text: " " + message, hex: "FFD75F")]
        }

        return [draw(header, width: width, color: color)]
            + zip(left, right).map(+)
            + [draw(footer, width: width, color: color)]
    }
}
