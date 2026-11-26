import Foundation

private func isMeetingHost(_ host: String) -> Bool {
    ["teams.microsoft.com", "teams.live.com", "zoom.us", "meet.google.com", "webex.com"]
        .contains { host == $0 || host.hasSuffix("." + $0) }
}

private func secureLinks(in text: String) -> [String] {
    text.matches(of: /https:\/\/[^\s<>"';,\)\]]+/).map { String($0.0) }
        .filter { URL(string: $0)?.host() != nil && sanitize($0) == $0 }
}

/// The link worth opening for an event. Only https is ever returned. Notes often
/// hold unrelated links, so from them only known meeting services are taken.
public func meetingLink(url: String?, location: String?, notes: String?) -> String? {
    let direct = secureLinks(in: [url, location].compactMap { $0 }.joined(separator: " "))
    let all = direct + secureLinks(in: notes ?? "")
    return all.first { isMeetingHost(URL(string: $0)!.host()!.lowercased()) } ?? direct.first
}
