import Foundation

/// What a natural phrase such as "last friday" or "next month" refers to.
public enum When: Equatable, Sendable {
    case day(Date)
    /// Several consecutive days.
    case days(from: Date, count: Int)
    case week(offset: Int)
    case month(offset: Int)
}

private let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
private let months = ["january", "february", "march", "april", "may", "june", "july", "august",
                      "september", "october", "november", "december"]
private let shortForms = [
    "sun": "sunday", "mon": "monday", "tue": "tuesday", "tues": "tuesday", "wed": "wednesday",
    "thu": "thursday", "thur": "thursday", "thurs": "thursday", "fri": "friday", "sat": "saturday",
    "jan": "january", "feb": "february", "mar": "march", "apr": "april", "jun": "june",
    "jul": "july", "aug": "august", "sep": "september", "sept": "september", "oct": "october",
    "nov": "november", "dec": "december", "tmr": "tomorrow", "tmrw": "tomorrow",
]
private let vocabulary = weekdays + months + [
    "today", "tomorrow", "yesterday", "next", "last", "this", "week", "weeks",
    "month", "months", "day", "days", "weekend", "ago", "in", "on", "the", "of",
]

private func distance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var row = Array(0...b.count)
    for i in 1...max(a.count, 1) where !a.isEmpty {
        var previous = row[0]
        row[0] = i
        for j in 1...max(b.count, 1) where !b.isEmpty {
            let current = row[j]
            row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
            previous = current
        }
    }
    return row[b.count]
}

/// Expands abbreviations and fixes small typos, only when one word is clearly closest.
private func normalize(_ word: String) -> String {
    if let full = shortForms[word] { return full }
    if vocabulary.contains(word) || word.count < 4 || word.contains(where: \.isNumber) { return word }
    let allowed = word.count < 6 ? 1 : 2
    let scored = vocabulary.map { ($0, distance(word, $0)) }.filter { $0.1 <= allowed }
    guard let best = scored.map(\.1).min() else { return word }
    let closest = scored.filter { $0.1 == best }
    return closest.count == 1 ? closest[0].0 : word
}

/// Returns nil when the phrase is not understood; it never guesses a date.
public func parseWhen(_ phrase: String, now: Date, calendar: Calendar) -> When? {
    let lower = phrase.lowercased()
    let today = calendar.startOfDay(for: now)
    func add(_ component: Calendar.Component, _ value: Int, to date: Date) -> Date {
        calendar.date(byAdding: component, value: value, to: date)!
    }
    func exactDate(_ year: Int, _ month: Int, _ day: Int) -> When? {
        let parts = DateComponents(year: year, month: month, day: day)
        guard (1900...2200).contains(year), let date = calendar.date(from: parts) else { return nil }
        // Reject things like February 30 instead of rolling into March.
        let check = calendar.dateComponents([.month, .day], from: date)
        return check.month == month && check.day == day ? .day(date) : nil
    }

    if let m = lower.wholeMatch(of: /\s*(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})\s*/) {
        return exactDate(Int(m.1)!, Int(m.2)!, Int(m.3)!)
    }

    var words = lower.split { " ,.\t".contains($0) }
        .map { word -> String in
            let text = String(word)
            if let m = text.wholeMatch(of: /(\d{1,2})(st|nd|rd|th)/) { return String(m.1) }
            return normalize(text)
        }
        .filter { !["on", "the", "of"].contains($0) }

    // "next 3 days", "in the next 3 days" and "next in 3 days" all mean a span.
    if words.contains("next") || words.contains("last") { words.removeAll { $0 == "in" } }
    if words.count == 3, ["next", "last"].contains(words[0]), let count = Int(words[1]), (1...62).contains(count) {
        let length: Int
        switch words[2] {
        case "day", "days": length = count
        case "week", "weeks": length = count * 7
        default: return nil
        }
        guard length <= 62 else { return nil }
        // The span starts tomorrow, or ends yesterday.
        return .days(from: add(.day, words[0] == "next" ? 1 : -length, to: today), count: length)
    }
    /// The Saturday and Sunday meant by "this", "next" or "last" weekend.
    func weekend(_ which: String) -> When {
        let weekday = calendar.component(.weekday, from: today) // 1 is Sunday
        var saturday = add(.day, weekday == 1 ? -1 : 7 - weekday, to: today)
        let underway = weekday == 1 || weekday == 7
        if which == "next" && underway { saturday = add(.day, 7, to: saturday) }
        if which == "last" { saturday = add(.day, -7, to: saturday) }
        return .days(from: saturday, count: 2)
    }

    let thisYear = calendar.component(.year, from: now)
    func monthNumber(_ word: String) -> Int? { months.firstIndex(of: word).map { $0 + 1 } }
    func monthView(_ month: Int, _ year: Int) -> When? {
        guard (1900...2200).contains(year) else { return nil }
        return .month(offset: (year - thisYear) * 12 + month - calendar.component(.month, from: now))
    }
    /// Days from today to the named weekday, 0...6 ahead.
    func ahead(_ index: Int) -> Int {
        (index + 1 - calendar.component(.weekday, from: today) + 7) % 7
    }
    func relative(_ count: Int, _ unit: String) -> When? {
        guard abs(count) <= 5000 else { return nil }
        switch unit {
        case "day", "days": return .day(add(.day, count, to: today))
        case "week", "weeks": return .day(add(.day, count * 7, to: today))
        case "month", "months": return .day(add(.month, count, to: today))
        default: return nil
        }
    }

    switch words.count {
    case 1:
        switch words[0] {
        case "today": return .day(today)
        case "weekend": return weekend("this")
        case "tomorrow": return .day(add(.day, 1, to: today))
        case "yesterday": return .day(add(.day, -1, to: today))
        default:
            if let i = weekdays.firstIndex(of: words[0]) { return .day(add(.day, ahead(i), to: today)) }
            if let month = monthNumber(words[0]) { return monthView(month, thisYear) }
        }
    case 2:
        let (first, second) = (words[0], words[1])
        if ["next", "last", "this"].contains(first) {
            let step = first == "next" ? 1 : first == "last" ? -1 : 0
            if second == "weekend" { return weekend(first) }
            if second == "week" { return .week(offset: step) }
            if second == "month" { return .month(offset: step) }
            if let i = weekdays.firstIndex(of: second) {
                var days = ahead(i)
                if step == 1 && days == 0 { days = 7 }
                if step == -1 { days -= 7 }
                return .day(add(.day, days, to: today))
            }
        }
        if let month = monthNumber(first), let number = Int(second) {
            return number > 31 ? monthView(month, number) : exactDate(thisYear, month, number)
        }
        if let day = Int(first), let month = monthNumber(second) { return exactDate(thisYear, month, day) }
    case 3:
        if words[0] == "in", let count = Int(words[1]), count >= 0 { return relative(count, words[2]) }
        if words[2] == "ago", let count = Int(words[0]), count >= 0 { return relative(-count, words[1]) }
        if let month = monthNumber(words[0]), let day = Int(words[1]), let year = Int(words[2]) {
            return exactDate(year, month, day)
        }
        if let day = Int(words[0]), let month = monthNumber(words[1]), let year = Int(words[2]) {
            return exactDate(year, month, day)
        }
    default:
        break
    }
    return nil
}
