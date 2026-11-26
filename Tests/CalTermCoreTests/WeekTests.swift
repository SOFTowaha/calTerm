import Foundation
import Testing
@testable import CalTermCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/St_Johns")!
    return c
}()
private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}
private func event(_ title: String, _ day: Int, _ from: Int, _ to: Int, _ hex: String = "5FD7FF") -> Event {
    Event(title: title, start: date(day, from), end: date(day, to), calendar: "A", color: hex)
}
private let days = (22...28).map { date($0) }
private func week(_ events: [Event], width: Int = 120) -> [String] {
    renderWeek(events, days: days, now: date(25, 12, 40), width: width, calendar: cal,
               locale: Locale(identifier: "en_CA")).split(separator: "\n").map(String.init)
}
private let sample = [
    Event(title: "Holiday", start: date(26), end: date(27), isAllDay: true, calendar: "H", color: "87D787"),
    event("Planning meeting", 23, 9, 11), event("Standup", 23, 11, 12),
    event("Code review", 25, 13, 15), event("Design talk", 25, 14, 16), event("Third", 25, 14, 15),
    event("Fourth", 25, 14, 15), event("会議 🎉", 27, 10, 11), event("Late gym", 24, 20, 21),
]

@Test(arguments: [64, 90, 120, 200])
func weekLinesHaveEqualWidth(width: Int) {
    let lines = week(sample, width: width).dropFirst()
    #expect(Set(lines.map(displayWidth)).count == 1)
    #expect(displayWidth(lines.first!) <= width)
    if ProcessInfo.processInfo.environment["PREVIEW"] != nil && width == 120 {
        print(week(sample, width: width).joined(separator: "\n"))
    }
}

@Test func eventsSitAtTheirHours() {
    let lines = week([event("Review", 25, 13, 15)])
    let start = lines.firstIndex { $0.contains(" 1 pm") }!
    #expect(lines[start].contains("▌Review"))
    // Two hours are four half-hour rows.
    #expect(lines.filter { $0.contains("▌") }.count == 4)
    #expect(lines.contains { $0.contains("▶12:40p") })
}

@Test func hoursStretchToFitEvents() {
    #expect(!week([]).contains { $0.contains(" 7 am") || $0.contains(" 8 pm") })
    let lines = week([event("Early", 23, 6, 7), event("Late", 23, 20, 21)])
    #expect(lines.contains { $0.contains(" 6 am") } && lines.contains { $0.contains(" 8 pm") })
}

@Test func overlapsShareTheColumnAndCountTheRest() {
    let output = week([event("One", 25, 13, 15), event("Two", 25, 13, 15), event("Three", 25, 13, 15)], width: 130)
        .joined(separator: "\n")
    #expect(output.contains("▌One") && output.contains("▌Thr"))
    #expect(output.contains("+1 more"))
}

@Test func workingHoursAreMarked() {
    let lines = week([event("Evening", 25, 18, 19)])
    #expect(lines.contains { $0.contains("┃ 9 am") })
    #expect(lines.contains { $0.contains("┃ 4 pm") })
    #expect(!lines.contains { $0.contains("┃ 8 am") || $0.contains("┃ 5 pm") })
    // Nine to five is sixteen half-hour rows.
    #expect(lines.filter { $0.hasPrefix("│┃") }.count == 15) // one row shows the current time instead
    #expect(lines.contains { $0.contains("▌Evening") })
}

@Test func workHourSetting() {
    #expect(workHours(nil) == 9..<17)
    #expect(workHours("8-16") == 8..<16)
    #expect(workHours("17-9") == 9..<17)
    #expect(workHours("junk") == 9..<17)
}
