import Foundation

public struct Event: Equatable, Sendable, Encodable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendar: String
    public var location: String?
    /// Calendar colour as RRGGBB.
    public var color: String?
    /// An https link to join or view the event.
    public var link: String?

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false,
                calendar: String, location: String? = nil, color: String? = nil,
                link: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.location = location
        self.color = color
        self.link = link
    }
}

public enum Command: String, CaseIterable, Sendable {
    case month, week, today, next, calendars, ui, help, version
}

public struct Options: Equatable, Sendable {
    public var command: Command
    public var json: Bool
    /// Months or weeks away from the current one.
    public var offset: Int = 0
    public var color: Bool = true
    public var icons: Bool = true
    /// Set when a particular day was asked for.
    public var date: Date? = nil
    /// How many days to list, starting at `date`.
    public var days: Int = 1
}

public struct UsageError: Error, Equatable {
    public let message: String
}

public let appVersion = "0.1.0"

public let usage = """
usage: ct [command or date] [+N|-N] [--json] [--no-color] [--no-icons]

  ui          full-screen calendar (? shows the keys)
  month       month grid (default); +1 is next month, -1 last month
  week        hour-by-hour week grid; +1 is next week
  day         list today's events, or a date's: day nov 5 (also: today)
  next        the current or next timed event (looks 30 days ahead)
  calendars   list your calendars and their accounts
  help        show this text
  --version   show the version

dates:  tomorrow, yesterday, friday, next friday, last friday,
        nov 11, 23 november 2025, 2025-11-23, in 3 days, 2 weeks ago,
        next week, last month, december, december 2027,
        weekend, next weekend, next 3 days, last 2 weeks
"""

public func parse(_ arguments: [String], now: Date = Date(),
                  calendar: Calendar = .current) throws -> Options {
    var words: [String] = []
    var options = Options(command: .month, json: false)
    for argument in arguments {
        if argument == "--json" {
            options.json = true
        } else if argument == "--no-icons" {
            options.icons = false
        } else if argument == "--no-color" {
            options.color = false
        } else if argument == "--version" {
            return Options(command: .version, json: false)
        } else if argument == "-h" || argument == "--help" {
            return Options(command: .help, json: false)
        } else if let first = argument.first, first == "+" || first == "-",
                  let value = Int(argument), abs(value) <= 1200 {
            options.offset = value
        } else if argument.hasPrefix("-") {
            throw UsageError(message: "unknown option: \(sanitize(argument))")
        } else {
            words.append(argument)
        }
    }
    // "day" alone is today; "day nov 5" is the same as "nov 5".
    if words.first?.lowercased() == "day" {
        words.removeFirst()
        if words.isEmpty { words = ["today"] }
    }
    if words.count == 1, let command = Command(rawValue: words[0].lowercased()) {
        options.command = command
    } else if !words.isEmpty {
        let phrase = words.joined(separator: " ")
        guard options.offset == 0, let when = parseWhen(phrase, now: now, calendar: calendar) else {
            throw UsageError(message: "don't understand: \(sanitize(phrase))")
        }
        switch when {
        case .day(let date): (options.command, options.date) = (.today, date)
        case .days(let from, let count): (options.command, options.date, options.days) = (.today, from, count)
        case .week(let offset): (options.command, options.offset) = (.week, offset)
        case .month(let offset): (options.command, options.offset) = (.month, offset)
        }
        return options
    }
    if options.offset != 0 && options.command != .month && options.command != .week {
        throw UsageError(message: "+N and -N only work with month and week")
    }
    return options
}

/// Event text can come from other people (invites), so remove anything that
/// could drive the terminal or reorder what is displayed.
public func sanitize(_ text: String) -> String {
    var result = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D, 0x2028, 0x2029:
            result.append(" ")
        case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
            continue
        default:
            result.append(scalar)
        }
    }
    return String(result)
}

public func range(for command: Command, now: Date, calendar: Calendar) -> DateInterval {
    let today = calendar.startOfDay(for: now)
    func days(_ count: Int, after date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date)!
    }
    switch command {
    case .week: return DateInterval(start: today, end: days(7, after: today))
    case .next: return DateInterval(start: now, end: days(30, after: now))
    default: return DateInterval(start: today, end: days(1, after: today))
    }
}

public func sorted(_ events: [Event]) -> [Event] {
    events.sorted {
        ($0.start, $0.isAllDay ? 0 : 1, $0.title) < ($1.start, $1.isAllDay ? 0 : 1, $1.title)
    }
}

public func nextEvent(in events: [Event], now: Date) -> Event? {
    sorted(events).first { !$0.isAllDay && $0.end > now }
}

/// Groups events by day. An event that began before `from` is listed under `from`.
public func render(_ events: [Event], from: Date, calendar: Calendar,
                   locale: Locale = .current, color: Bool = false, icons: Bool = false) -> String {
    if events.isEmpty { return "No events." }

    func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    let day = formatter("EEEMMMd")
    let time = formatter("jmm")

    var lines: [String] = []
    var currentDay: Date?
    let visible = sorted(events).map { (day: calendar.startOfDay(for: max($0.start, from)), event: $0) }
    // Stable order: by displayed day, keeping the start-time order within a day.
    for (shownDay, event) in visible.enumerated()
        .sorted(by: { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) })
        .map(\.element) {
        if shownDay != currentDay {
            if currentDay != nil { lines.append("") }
            lines.append(day.string(from: shownDay))
            currentDay = shownDay
        }
        // An event ending exactly at midnight does not count as the following day.
        let lastDay = calendar.startOfDay(for: max(event.start, event.end.addingTimeInterval(-1)))
        let startsEarlier = event.start < shownDay
        let endsLater = lastDay > shownDay

        var when: String
        if event.isAllDay {
            when = "all day"
        } else if startsEarlier {
            when = endsLater ? "continues" : "until \(time.string(from: event.end))"
        } else {
            when = time.string(from: event.start)
            if !endsLater { when += " - " + time.string(from: event.end) }
        }
        var line = "  \(paint(icons ? icon(for: event).rawValue : "●", event.color, color)) \(when)  \(sanitize(event.title))"
        if endsLater { line += " (through \(day.string(from: lastDay)))" }
        if let location = event.location, !location.isEmpty { line += " @ \(sanitize(location))" }
        line += " [\(sanitize(event.calendar))]"
        lines.append(line)
    }
    return lines.joined(separator: "\n")
}

public func json<T: Encodable>(_ value: T, timeZone: TimeZone = .current) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        var container = encoder.singleValueContainer()
        try container.encode(f.string(from: date))
    }
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

public func sanitized(_ event: Event) -> Event {
    var copy = event
    copy.title = sanitize(event.title)
    copy.calendar = sanitize(event.calendar)
    copy.location = event.location.map(sanitize)
    return copy
}
