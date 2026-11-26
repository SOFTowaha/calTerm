import Foundation

private let line = "5F6F8F"
private let workShade = "2E3F5F"
private let workMark = "87D787"

/// Reads hours such as "9-17"; anything unusable gives 9 to 5.
public func workHours(_ text: String?) -> Range<Int> {
    let parts = (text ?? "").split(separator: "-").compactMap { Int($0) }
    guard parts.count == 2, parts[0] >= 0, parts[1] <= 24, parts[0] < parts[1] else { return 9..<17 }
    return parts[0]..<parts[1]
}

private struct Block {
    let event: Event
    let first: Int // half-hour slots from midnight
    let end: Int
    var lane = 0
    var lanes = 1
    var more = 0 // overlapping events that did not fit
}

/// Places overlapping events side by side, in at most `limit` lanes.
private func arrange(_ blocks: [Block], limit: Int) -> [Block] {
    var result: [Block] = []
    var cluster: [Block] = []
    var laneEnds: [Int] = []
    var clusterEnd = 0

    func flush() {
        for var block in cluster {
            block.lanes = max(1, laneEnds.count)
            result.append(block)
        }
        cluster = []
        laneEnds = []
    }
    for var block in blocks.sorted(by: { ($0.first, $1.end) < ($1.first, $0.end) }) {
        if block.first >= clusterEnd { flush() }
        clusterEnd = max(clusterEnd, block.end)
        if let free = laneEnds.firstIndex(where: { $0 <= block.first }) {
            block.lane = free
            laneEnds[free] = block.end
        } else if laneEnds.count < limit {
            block.lane = laneEnds.count
            laneEnds.append(block.end)
        } else {
            if let i = cluster.lastIndex(where: { $0.lane == limit - 1 }) { cluster[i].more += 1 }
            continue
        }
        cluster.append(block)
    }
    flush()
    return result
}

/// Black or white, whichever reads better on the background.
private func ink(on hex: String) -> String {
    let v = Int(hex, radix: 16) ?? 0
    let light = 299 * (v >> 16) + 587 * ((v >> 8) & 255) + 114 * (v & 255)
    return light > 140_000 ? "000000" : "FFFFFF"
}

/// A week as a time grid: hours down the side, one column per day.
public func renderWeek(_ all: [Event], days: [Date], now: Date, width: Int, calendar: Calendar,
                       locale: Locale = .current, color: Bool = false, icons: Bool = false,
                       work: Range<Int> = 9..<17) -> String {
    let timeWidth = 7
    let cell = max(6, (width - timeWidth - 9) / 7)
    let total = timeWidth + cell * 7 + 9

    func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    func nextDay(_ day: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: day)! }
    func slot(_ date: Date, roundingUp: Bool) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour! * 60 + parts.minute! + (roundingUp ? 29 : 0)) / 30
    }
    func fillsDay(_ event: Event, _ day: Date) -> Bool {
        event.isAllDay || (event.start <= day && event.end >= nextDay(day))
    }

    let allDay = days.map { day in events(on: day, from: all, calendar: calendar).filter { fillsDay($0, day) } }
    let timed: [[Block]] = days.map { day in
        let blocks = events(on: day, from: all, calendar: calendar).filter { !fillsDay($0, day) }.map { event in
            let first = event.start < day ? 0 : min(slot(event.start, roundingUp: false), 47)
            let end = event.end >= nextDay(day) ? 48 : slot(event.end, roundingUp: true)
            return Block(event: event, first: first, end: max(end, first + 1))
        }
        return arrange(blocks, limit: max(1, cell / 7))
    }

    // Working hours, stretched to cover anything earlier or later, on whole hours.
    let from = min(16, timed.joined().map(\.first).min() ?? 16) / 2 * 2
    let to = (max(36, timed.joined().map(\.end).max() ?? 36) + 1) / 2 * 2

    func row(_ label: Span, _ columns: [[Span]]) -> String {
        let bar = Span(text: "│", hex: line)
        var spans = [bar, label]
        for column in columns { spans += [bar] + column }
        return draw(spans + [bar], width: total, color: color)
    }
    func rule(_ left: String, _ joint: String, _ right: String) -> String {
        let parts = [timeWidth] + Array(repeating: cell, count: 7)
        return paint(left + parts.map { String(repeating: "─", count: $0) }.joined(separator: joint) + right, line, color)
    }
    func blank(_ text: String = "") -> Span { Span(text: fit(text, timeWidth)) }
    func filled(_ text: String, _ hex: String?, _ size: Int, underline: Bool = false, bold: Bool = false) -> Span {
        let background = hex ?? "8A8A8A"
        // Without colour a bar marks the extent of the block instead.
        return Span(text: fit((color ? " " : "▌") + text, size), hex: color ? ink(on: background) : nil,
                    bold: bold, underline: underline, background: color ? background : nil)
    }
    func title(_ event: Event) -> String {
        (icons ? icon(for: event).rawValue + " " : "") + sanitize(event.title)
    }

    let heading = "\(formatter("MMMd").string(from: days[0])) – \(formatter("MMMdyyyy").string(from: days[6]))"
    var lines = [String(repeating: " ", count: max(0, (total - displayWidth(heading)) / 2)) + heading,
                 rule("╭", "┬", "╮")]
    lines.append(row(blank(), days.map { day in
        let today = calendar.isDate(day, inSameDayAs: now)
        let text = " \(formatter("EEE").string(from: day)) \(calendar.component(.day, from: day))"
        return [Span(text: fit(text, cell), hex: today ? "FF87AF" : nil, bold: true, inverse: today)]
    }))
    lines.append(rule("├", "┼", "┤"))

    let allDayRows = min(3, allDay.map(\.count).max() ?? 0)
    for i in 0..<allDayRows {
        lines.append(row(blank(i == 0 ? "all day" : ""), allDay.map { list in
            if i == allDayRows - 1 && list.count > allDayRows {
                return [Span(text: fit(" +\(list.count - i) more", cell), dim: true)]
            }
            return [i < list.count ? filled(title(list[i]), list[i].color, cell) : Span(text: fit("", cell))]
        }))
    }
    if allDayRows > 0 { lines.append(rule("├", "┼", "┤")) }

    let nowSlot = slot(now, roundingUp: false)
    let thisWeek = days.contains { calendar.isDate($0, inSameDayAs: now) }
    for current in from..<to {
        let onHour = current % 2 == 0
        let working = work.contains(current / 2)
        var label = Span(text: fit(working ? "┃" : "", timeWidth), hex: working ? workMark : nil)
        if onHour {
            let hour = current / 2
            let name = String(format: "%2d %@", (hour + 11) % 12 + 1, hour < 12 ? "am" : "pm")
            label = Span(text: fit((working ? "┃" : " ") + name, timeWidth), hex: working ? workMark : nil, dim: !working)
        }
        if thisWeek && current == nowSlot {
            label = Span(text: fit("▶" + clockText(now, calendar: calendar), timeWidth), hex: "FF87AF", bold: true)
        }
        lines.append(row(label, zip(days, timed).map { day, blocks in
            // An empty stretch: hours have a faint line, working time is shaded.
            let weekend = [1, 7].contains(calendar.component(.weekday, from: day))
            func gap(_ size: Int) -> Span {
                Span(text: String(repeating: onHour ? "┈" : " ", count: size), hex: line,
                     background: color && working && !weekend ? workShade : nil)
            }
            let active = blocks.filter { $0.first <= current && current < $0.end }
            guard let lanes = active.first?.lanes else { return [gap(cell)] }
            return (0..<lanes).map { lane in
                // One column of space between neighbouring lanes.
                let size = cell / lanes + (lane == lanes - 1 ? cell % lanes : 0)
                // The last column of a lane separates it from its neighbour.
                let usable = size - (lane < lanes - 1 ? 1 : 0)
                guard let block = active.first(where: { $0.lane == lane }) else { return gap(usable) }
                let height = block.end - block.first
                let index = current - block.first
                let inner = usable - 1
                var parts = wrap(title(block.event), width: max(1, inner), lines: height > 2 ? height - 1 : height)
                if height > parts.count {
                    parts.append(clockText(block.event.start, calendar: calendar))
                }
                if block.more > 0 {
                    if height == 1 { parts = ["+\(block.more + 1) events"] }
                    else { parts = Array(parts.prefix(height - 1)) + ["+\(block.more) more"] }
                }
                let text = index < parts.count ? parts[index] : ""
                return filled(text, block.event.color, usable,
                              underline: index == height - 1, bold: index == 0)
            }.enumerated().flatMap { lane, span in lane < lanes - 1 ? [span, gap(1)] : [span] }
        }))
    }
    lines.append(rule("╰", "┴", "╯"))
    return lines.joined(separator: "\n")
}
