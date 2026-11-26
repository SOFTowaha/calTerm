import Foundation
import Testing
@testable import CalTermCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/St_Johns")!
    c.firstWeekday = 1
    return c
}()
private func date(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}
private let sample = [
    Event(title: "Planning meeting with a very long title", start: date(11, 25, 13), end: date(11, 25, 14), calendar: "A", color: "FF8800"),
    Event(title: "会議 🎉 café", start: date(11, 25, 9), end: date(11, 25, 10), calendar: "A"),
    Event(title: "Holiday", start: date(11, 11), end: date(11, 12), isAllDay: true, calendar: "B"),
]

@Test func mergesCopiesFromSeveralAccounts() {
    var copy = sample[0]
    copy.calendar = "B"
    let merged = deduplicated([sample[0], sample[0], copy, sample[1]])
    #expect(merged.count == 2)
    #expect(merged[0].calendar == "A, B")
}

@Test func monthAndWeekDays() {
    let month = gridWeeks(for: .month, offset: 0, now: date(11, 25), calendar: cal)
    #expect(month.weeks.count == 5)
    #expect(month.weeks[0][0] == date(11, 1))
    #expect(gridWeeks(for: .month, offset: 1, now: date(11, 25), calendar: cal).anchor == date(12, 1))
    let week = gridWeeks(for: .week, offset: -1, now: date(11, 25), calendar: cal)
    #expect(week.weeks == [(15...21).map { date(11, $0) }])
}

@Test(arguments: [64, 100, 160])
func gridLinesHaveEqualWidth(width: Int) {
    let grid = gridWeeks(for: .month, offset: 0, now: date(11, 25), calendar: cal)
    let output = renderGrid(sample, anchor: grid.anchor, weeks: grid.weeks, now: date(11, 25),
                            width: width, calendar: cal, locale: Locale(identifier: "en_CA"))
    let widths = Set(output.split(separator: "\n").dropFirst().map { displayWidth(String($0)) })
    #expect(widths.count == 1)
    #expect(widths.first! <= width)
}

@Test func offsets() throws {
    #expect(try parse(["week", "+2"]).offset == 2)
    #expect(try parse(["-1"]).offset == -1)
    #expect(throws: UsageError.self) { try parse(["today", "+1"]) }
}
