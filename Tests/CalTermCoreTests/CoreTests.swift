import Foundation
import Testing
@testable import CalTermCore

private let zone = TimeZone(identifier: "America/St_Johns")!
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    return c
}()
private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}
private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> Event {
    Event(title: title, start: start, end: end, isAllDay: allDay, calendar: "Work")
}
private func text(_ events: [Event], from: Date) -> String {
    render(events, from: from, calendar: cal, locale: Locale(identifier: "en_GB"))
}

@Test func parsing() throws {
    #expect(try parse([]) == Options(command: .month, json: false))
    #expect(try parse(["--json", "week"]) == Options(command: .week, json: true))
    #expect(try parse(["week", "--help"]).command == .help)
    #expect(throws: UsageError.self) { try parse(["banana"]) }
    #expect(throws: UsageError.self) { try parse(["today", "week"]) }
}

@Test func stripsTerminalControls() {
    #expect(sanitize("a\u{1B}[31mred\u{07}") == "a[31mred")
    #expect(sanitize("one\ntwo\tthree") == "one two three")
    #expect(sanitize("x\u{202E}y\u{9B}z") == "xyz")
    #expect(sanitize("Café 会議") == "Café 会議")
}

@Test func weekRangeSurvivesDaylightSavingChange() {
    // Clocks go back on 1 November 2026, so this week is an hour longer.
    let week = range(for: .week, now: date(10, 29, 15), calendar: cal)
    #expect(week.start == date(10, 29))
    #expect(week.end == date(11, 5))
    #expect(week.duration == 7 * 86400 + 3600)
}

@Test func nextSkipsAllDayAndFinishedEvents() {
    let events = [
        event("holiday", date(11, 25), date(11, 25, 23, 59), allDay: true),
        event("done", date(11, 25, 8), date(11, 25, 9)),
        event("later", date(11, 25, 14), date(11, 25, 15)),
        event("ongoing", date(11, 25, 9, 30), date(11, 25, 11)),
    ]
    #expect(nextEvent(in: events, now: date(11, 25, 10))?.title == "ongoing")
    #expect(nextEvent(in: [], now: date(11, 25, 10)) == nil)
}

@Test func rendersByDay() {
    let output = text([
        event("standup", date(11, 26, 9), date(11, 26, 9, 15)),
        event("review", date(11, 25, 13), date(11, 25, 14)),
    ], from: date(11, 25))
    let lines = output.split(separator: "\n").map(String.init)
    #expect(lines.count == 4)
    #expect(lines[1].contains("● 13:00 - 14:00  review [Work]"))
    #expect(lines[3].contains("● 09:00 - 09:15  standup [Work]"))
    #expect(text([], from: date(11, 25)) == "No events.")
}

@Test func rendersMultiDayEvents() {
    let output = text([event("conference", date(11, 24, 9), date(11, 27, 17))], from: date(11, 25))
    #expect(output.contains("continues  conference (through"))
    let overnight = text([event("shift", date(11, 24, 22), date(11, 25, 6))], from: date(11, 25))
    #expect(overnight.contains("until 06:00  shift [Work]"))
    let midnight = text([event("late", date(11, 25, 23), date(11, 26))], from: date(11, 25))
    #expect(!midnight.contains("through"))
}

@Test func jsonKeepsLocalOffset() throws {
    let output = try json([event("a", date(11, 25, 9), date(11, 25, 10))], timeZone: zone)
    #expect(output.contains("2026-11-25T09:00:00-03:30"))
}

@Test func versionFlag() throws {
    #expect(try parse(["--version"]).command == .version)
}
