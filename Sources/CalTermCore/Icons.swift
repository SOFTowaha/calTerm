import Foundation

/// Nerd Font (Font Awesome) glyphs, chosen from an event's words.
public enum Icon: String, CaseIterable, Sendable {
    case birthday = "\u{F1FD}"
    case holiday = "\u{F024}"
    case travel = "\u{F072}"
    case health = "\u{F0FA}"
    case fitness = "\u{F21E}"
    case food = "\u{F0F5}"
    case code = "\u{F121}"
    case study = "\u{F19D}"
    case call = "\u{F095}"
    case video = "\u{F03D}"
    case people = "\u{F0C0}"
    case other = "\u{F133}"
}

public func icon(for event: Event) -> Icon {
    let calendar = event.calendar.lowercased()
    if calendar.contains("birthday") { return .birthday }
    if calendar.contains("holiday") { return .holiday }

    // Whole words only, so "Birmingham" is not a gym and "Callum" is not a call.
    let words = " " + event.title.lowercased()
        .split { !$0.isLetter && !$0.isNumber }
        .joined(separator: " ") + " "
    func has(_ terms: [String]) -> Bool { terms.contains { words.contains(" \($0) ") } }

    if has(["birthday"]) { return .birthday }
    if has(["holiday"]) { return .holiday }
    if has(["flight", "airport", "travel", "trip"]) { return .travel }
    if has(["doctor", "dentist", "clinic", "appointment", "physio"]) { return .health }
    if has(["gym", "workout", "yoga", "run", "swim", "badminton"]) { return .fitness }
    if has(["breakfast", "lunch", "dinner", "coffee", "potluck"]) { return .food }
    if has(["code", "coding", "hackathon"]) { return .code }
    if has(["class", "lecture", "lab", "exam", "seminar", "course", "workshop", "thesis"]) { return .study }
    if has(["call", "phone"]) { return .call }

    let place = ((event.link ?? "") + " " + (event.location ?? "")).lowercased()
    if ["teams", "zoom", "meet.google", "webex"].contains(where: place.contains) { return .video }
    if has(["meeting", "standup", "sync", "catch up", "weekly", "biweekly", "planning"]) { return .people }
    return .other
}
