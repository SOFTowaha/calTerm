import Foundation
import Testing
@testable import CalTermCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/St_Johns")!
    return c
}()
private func date(_ day: Int, _ hour: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
}
private func app() -> App {
    var app = App(now: date(25, 8), calendar: cal)
    app.events = [
        Event(title: "Standup 会議", start: date(25, 9), end: date(25, 10), calendar: "Work", color: "5FD7FF",
              link: "https://teams.microsoft.com/l/x"),
        Event(title: "Gym", start: date(25, 16), end: date(25, 17), calendar: "Home", color: "FF87AF"),
        Event(title: "Review", start: date(27, 13), end: date(27, 14), calendar: "Work", location: "Room 2"),
    ]
    return app
}
private func type(_ text: String, into app: inout App) {
    for c in text { _ = app.handle(.character(c)) }
}

@Test func movingAndSelecting() {
    var a = app()
    _ = a.handle(.tab)
    #expect(a.selected == 1)
    _ = a.handle(.right)
    #expect(a.day == date(26) && a.selected == 0)
    _ = a.handle(.down)
    #expect(a.day == cal.date(from: DateComponents(year: 2026, month: 12, day: 3))!)
    _ = a.handle(.character("t"))
    #expect(a.day == date(25))
    #expect(a.handle(.character("q")) == .quit)
}

@Test func openingOnlyWhenThereIsALink() {
    var a = app()
    #expect(a.handle(.character("o")) == .open("https://teams.microsoft.com/l/x"))
    _ = a.handle(.tab)
    #expect(a.handle(.enter) == .none)
}

@Test func gotoAndSearch() {
    var a = app()
    _ = a.handle(.character("g"))
    type("next friday", into: &a)
    _ = a.handle(.enter)
    #expect(a.day == date(27) && a.mode == .browse)
    _ = a.handle(.character("/"))
    type("gym", into: &a) // letters such as q must not quit while typing
    _ = a.handle(.enter)
    #expect(a.mode == .results)
    _ = a.handle(.enter)
    #expect(a.day == date(25) && a.agenda[a.selected].title == "Gym")
}

@Test(arguments: [(72, 22), (110, 30), (200, 55)])
func screenFillsTheWindowExactly(width: Int, height: Int) {
    var a = app()
    for key: Key in [.tab, .character("?"), .escape, .character("g"), .escape] {
        _ = a.handle(key)
        let lines = a.frame(width: width, height: height, locale: Locale(identifier: "en_CA"), color: false)
        #expect(lines.count == height)
        #expect(Set(lines.map(displayWidth)) == [width])
    }
    if ProcessInfo.processInfo.environment["PREVIEW"] != nil && width == 110 {
        print(a.frame(width: width, height: height, locale: Locale(identifier: "en_CA"), color: false).joined(separator: "\n"))
    }
}

@Test func keyDecoding() {
    #expect(decodeKeys(Array("\u{1B}[A\u{1B}[Zq".utf8)) == [.up, .backTab, .character("q")])
    #expect(decodeKeys([0x1B]) == [.escape])
    #expect(decodeKeys(Array("\u{1B}[15~".utf8)) == [])
}

@Test func onlySecureLinksAndOnlyMeetingsFromNotes() {
    #expect(meetingLink(url: nil, location: "http://example.com", notes: nil) == nil)
    #expect(meetingLink(url: "file:///etc/passwd", location: nil, notes: "https://example.com/help") == nil)
    #expect(meetingLink(url: nil, location: "Room 1", notes: "Join <https://us02web.zoom.us/j/1>")
            == "https://us02web.zoom.us/j/1")
}
