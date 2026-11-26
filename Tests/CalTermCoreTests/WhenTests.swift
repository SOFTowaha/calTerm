import Foundation
import Testing
@testable import CalTermCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/St_Johns")!
    return c
}()
private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day))!
}
private let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 17))! // a Wednesday

@Test(arguments: [
    ("tomorrow", 2026, 11, 26), ("tommorow", 2026, 11, 26), ("yesterday", 2026, 11, 24),
    ("friday", 2026, 11, 27), ("fri", 2026, 11, 27), ("next friday", 2026, 11, 27),
    ("last friday", 2026, 11, 20), ("last freiday", 2026, 11, 20),
    ("wednesday", 2026, 11, 25), ("next wednesday", 2026, 12, 2), ("last wednesday", 2026, 11, 18),
    ("nov 11", 2026, 11, 11), ("11 Nov", 2026, 11, 11), ("november 23 2025", 2025, 11, 23),
    ("Nov 23rd, 2025", 2025, 11, 23), ("23rd of november 2025", 2025, 11, 23),
    ("2025-11-23", 2025, 11, 23), ("in 3 days", 2026, 11, 28), ("3 weeks ago", 2026, 11, 4),
    ("in 2 months", 2027, 1, 25),
])
func days(phrase: String, year: Int, month: Int, day: Int) {
    #expect(parseWhen(phrase, now: now, calendar: cal) == .day(date(year, month, day)))
}

@Test func weeksAndMonths() {
    #expect(parseWhen("next week", now: now, calendar: cal) == .week(offset: 1))
    #expect(parseWhen("last month", now: now, calendar: cal) == .month(offset: -1))
    #expect(parseWhen("december", now: now, calendar: cal) == .month(offset: 1))
    #expect(parseWhen("january 2027", now: now, calendar: cal) == .month(offset: 2))
}

@Test(arguments: ["", "banana", "feb 30", "11/12", "nov 11 friday", "in many days", "2025-13-01", "in 999999 days"])
func refusesToGuess(phrase: String) {
    #expect(parseWhen(phrase, now: now, calendar: cal) == nil)
}

@Test func phrasesWorkQuotedOrNot() throws {
    let split = try parse(["last", "friday"], now: now, calendar: cal)
    #expect(split == (try parse(["last friday"], now: now, calendar: cal)))
    #expect(split.date == date(2026, 11, 20))
    #expect(try parse(["next"], now: now, calendar: cal).command == .next)
}

@Test(arguments: [
    ("weekend", 11, 28, 2), ("next weekend", 11, 28, 2), ("last weekend", 11, 21, 2),
    ("next 3 days", 11, 26, 3), ("next in 3 days", 11, 26, 3), ("in the next 3 days", 11, 26, 3),
    ("last 3 days", 11, 22, 3), ("next 2 weeks", 11, 26, 14),
])
func spans(phrase: String, month: Int, day: Int, count: Int) {
    #expect(parseWhen(phrase, now: now, calendar: cal) == .days(from: date(2026, month, day), count: count))
}

@Test func weekendWhileItIsHappening() {
    let sunday = date(2026, 11, 29)
    #expect(parseWhen("this weekend", now: sunday, calendar: cal) == .days(from: date(2026, 11, 28), count: 2))
    #expect(parseWhen("next weekend", now: sunday, calendar: cal) == .days(from: date(2026, 12, 5), count: 2))
}

@Test(arguments: [64, 100, 180])
func tableLinesHaveEqualWidth(width: Int) {
    let events = [
        Event(title: "会議 🎉 with a very long title that has to wrap onto more lines", start: date(2026, 11, 25),
              end: date(2026, 11, 26), isAllDay: true, calendar: "someone@example.com"),
        Event(title: "Review", start: now, end: now.addingTimeInterval(3600), calendar: "Home",
              location: "https://teams.microsoft.com/l/meetup-join/abcdef"),
    ]
    let output = renderTable(events, days: [date(2026, 11, 25)], now: now, width: width,
                             calendar: cal, locale: Locale(identifier: "en_CA"))
    let widths = Set(output.split(separator: "\n").map { displayWidth(String($0)) })
    #expect(widths == [min(width, 150)])
    #expect(output.contains("Teams"))
    #expect(!output.contains("https"))
    if ProcessInfo.processInfo.environment["PREVIEW"] != nil && width == 100 { print(output) }
}

@Test func linkNamesCheckTheRealHost() {
    #expect(shortLocation("https://us02web.zoom.us/j/1") == "Zoom link")
    #expect(shortLocation("https://evilzoom.us/j/1") == "evilzoom.us")
    #expect(shortLocation("Room 2") == "Room 2")
}

@Test func dayCommand() throws {
    #expect(try parse(["day"], now: now, calendar: cal).command == .today)
    #expect(try parse(["day", "nov", "5"], now: now, calendar: cal).date == date(2026, 11, 5))
    #expect(try parse(["nov", "5"], now: now, calendar: cal).date == date(2026, 11, 5))
}
