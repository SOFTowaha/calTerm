import Foundation

public enum Key: Equatable, Sendable {
    case up, down, left, right, enter, escape, backspace, tab, backTab, interrupt
    case character(Character)
}

/// Turns the bytes from one terminal read into key presses.
public func decodeKeys(_ bytes: [UInt8]) -> [Key] {
    let sequences: [(String, Key)] = [
        ("\u{1B}[A", .up), ("\u{1B}[B", .down), ("\u{1B}[C", .right), ("\u{1B}[D", .left),
        ("\u{1B}OA", .up), ("\u{1B}OB", .down), ("\u{1B}OC", .right), ("\u{1B}OD", .left),
        ("\u{1B}[Z", .backTab),
    ]
    var text = Substring(String(decoding: bytes, as: UTF8.self))
    var keys: [Key] = []
    while let first = text.unicodeScalars.first {
        if let (sequence, key) = sequences.first(where: { text.hasPrefix($0.0) }) {
            keys.append(key)
            text = Substring(text.unicodeScalars.dropFirst(sequence.unicodeScalars.count))
            continue
        }
        // Ignore other escape sequences (function keys and the like) as a whole.
        if first == "\u{1B}", let match = text.prefixMatch(of: /\u{1B}(\[[0-9;]*[~A-Za-z]|O[A-Za-z])/) {
            text = text[match.range.upperBound...]
            continue
        }
        switch first.value {
        case 0x1B: keys.append(.escape)
        case 0x0D, 0x0A: keys.append(.enter)
        case 0x7F, 0x08: keys.append(.backspace)
        case 0x09: keys.append(.tab)
        case 0x03: keys.append(.interrupt)
        case 0x00...0x1F: break
        default: keys.append(.character(Character(first)))
        }
        text = Substring(text.unicodeScalars.dropFirst())
    }
    return keys
}

public enum Action: Equatable, Sendable { case none, quit, reload, open(String) }

public struct App {
    public enum Mode: Equatable { case browse, goto, search, results, help }

    public var day: Date
    public var events: [Event] = []
    public var selected = 0
    public var mode = Mode.browse
    public var input = ""
    public var message = ""
    public var icons = true
    public let calendar: Calendar
    public var now: Date

    public init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
        self.day = calendar.startOfDay(for: now)
    }

    /// The span of events to load around the selected day.
    public var window: DateInterval {
        let month = calendar.dateInterval(of: .month, for: day)!.start
        return DateInterval(start: calendar.date(byAdding: .month, value: -2, to: month)!,
                            end: calendar.date(byAdding: .month, value: 4, to: month)!)
    }

    public var agenda: [Event] { CalTermCore.events(on: day, from: events, calendar: calendar) }

    public var results: [Event] {
        let query = input.lowercased()
        guard !query.isEmpty else { return [] }
        return sorted(events.filter {
            $0.title.lowercased().contains(query) || ($0.location ?? "").lowercased().contains(query)
        })
    }

    private mutating func move(_ component: Calendar.Component, _ value: Int) {
        day = calendar.startOfDay(for: calendar.date(byAdding: component, value: value, to: day)!)
        selected = 0
    }

    public mutating func handle(_ key: Key) -> Action {
        if key == .interrupt { return .quit }
        message = ""
        switch mode {
        case .help:
            mode = .browse
        case .goto, .search:
            switch key {
            case .escape: (mode, input) = (.browse, "")
            case .backspace: if !input.isEmpty { input.removeLast() }
            case .character(let c): if input.count < 60 { input.append(c) }
            case .enter where mode == .search:
                // Start at the first match from today onwards.
                selected = results.firstIndex { $0.end > now } ?? 0
                mode = results.isEmpty ? .browse : .results
                if results.isEmpty { (message, input) = ("No match for “\(input)”", "") }
            case .enter:
                jump(to: input)
                (mode, input) = (.browse, "")
                return .reload
            default: break
            }
        case .results:
            switch key {
            case .down, .character("j"), .tab: selected = min(selected + 1, max(results.count - 1, 0))
            case .up, .character("k"), .backTab: selected = max(selected - 1, 0)
            case .enter:
                if results.indices.contains(selected) {
                    let found = results[selected]
                    day = calendar.startOfDay(for: found.start)
                    (mode, input) = (.browse, "")
                    selected = agenda.firstIndex(of: found) ?? 0
                    return .reload
                }
            case .escape, .character("q"): (mode, input, selected) = (.browse, "", 0)
            default: break
            }
        case .browse:
            switch key {
            case .character("q"): return .quit
            case .left, .character("h"): move(.day, -1); return .reload
            case .right, .character("l"): move(.day, 1); return .reload
            case .up, .character("k"): move(.day, -7); return .reload
            case .down, .character("j"): move(.day, 7); return .reload
            case .character("p"): move(.month, -1); return .reload
            case .character("n"): move(.month, 1); return .reload
            case .character("t"): day = calendar.startOfDay(for: now); selected = 0; return .reload
            case .tab: if !agenda.isEmpty { selected = (selected + 1) % agenda.count }
            case .backTab: if !agenda.isEmpty { selected = (selected + agenda.count - 1) % agenda.count }
            case .character("g"): (mode, input) = (.goto, "")
            case .character("/"): (mode, input) = (.search, "")
            case .character("?"): mode = .help
            case .character("r"): message = "Refreshed"; return .reload
            case .character("o"), .enter:
                if agenda.indices.contains(selected), let link = agenda[selected].link {
                    message = "Opening \(URL(string: link)?.host() ?? "link")"
                    return .open(link)
                }
                message = "This event has no link"
            default: break
            }
        }
        return .none
    }

    private mutating func jump(to phrase: String) {
        switch parseWhen(phrase, now: now, calendar: calendar) {
        case .day(let date)?, .days(let date, _)?:
            day = date
        case .week(let offset)?:
            day = calendar.date(byAdding: .day, value: offset * 7, to: calendar.startOfDay(for: now))!
        case .month(let offset)?:
            let first = calendar.dateInterval(of: .month, for: now)!.start
            day = calendar.date(byAdding: .month, value: offset, to: first)!
        case nil:
            message = "Don't understand “\(sanitize(phrase))”"
            return
        }
        selected = 0
    }
}
