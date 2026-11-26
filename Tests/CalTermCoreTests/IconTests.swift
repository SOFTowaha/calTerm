import Foundation
import Testing
@testable import CalTermCore

private func make(_ title: String, calendar: String = "Home", location: String? = nil) -> Event {
    Event(title: title, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600),
          calendar: calendar, location: location)
}

@Test func iconsFollowTheEvent() {
    #expect(icon(for: make("Sam", calendar: "Birthdays")) == .birthday)
    #expect(icon(for: make("Black Friday", calendar: "Holidays in United States")) == .holiday)
    #expect(icon(for: make("Gym")) == .fitness)
    #expect(icon(for: make("Code Review w/Lee")) == .code)
    #expect(icon(for: make("Fall Lab meetings")) == .study)
    #expect(icon(for: make("Weekly Strategy", location: "Microsoft Teams Meeting")) == .video)
    #expect(icon(for: make("Catch-up")) == .people)
    #expect(icon(for: make("Birmingham with Callum")) == .other)
}

@Test func everyIconIsOneColumn() {
    #expect(Icon.allCases.allSatisfy { displayWidth($0.rawValue) == 1 })
}
