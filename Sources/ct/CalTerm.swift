import CalTermCore
import EventKit
import Foundation

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("ct: \(message)\n".utf8))
    exit(code)
}

@main
struct CalTerm {
    static func main() async {
        let options: Options
        do {
            options = try parse(Array(CommandLine.arguments.dropFirst()))
        } catch let error as UsageError {
            fail("\(error.message)\n\(usage)", code: 64)
        } catch {
            fail("\(error)", code: 64)
        }
        if options.command == .help {
            print(usage)
            return
        }

        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else {
            fail("no calendar access. Allow your terminal app under System Settings > "
                 + "Privacy & Security > Calendars (Full Access).", code: 77)
        }

        do {
            try run(options, store: store)
        } catch {
            fail("\(error)", code: 70)
        }
    }

    static func run(_ options: Options, store: EKEventStore) throws {
        let color = options.color && isatty(STDOUT_FILENO) == 1
            && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

        if options.command == .ui {
            runInterface(store: store,
                         color: options.color && ProcessInfo.processInfo.environment["NO_COLOR"] == nil,
                         icons: options.icons)
            return
        }

        // Icons are for people, so leave them out of piped output.
        let icons = options.icons && isatty(STDOUT_FILENO) == 1

        if options.command == .calendars {
            let lines = store.calendars(for: .event)
                .map { (name: sanitize($0.title), account: sanitize($0.source?.title ?? ""), hex: hex($0.cgColor)) }
                .sorted { ($0.account, $0.name) < ($1.account, $1.name) }
            if options.json {
                print(try json(lines.map { ["name": $0.name, "account": $0.account] }))
            } else {
                for line in lines {
                    print("\(paint("●", line.hex, color)) \(line.name)  (\(line.account))")
                }
            }
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let isGrid = options.command == .month || options.command == .week
        let grid = gridWeeks(for: options.command, offset: options.offset, now: now, calendar: calendar)
        let interval = isGrid
            ? DateInterval(start: grid.weeks[0][0],
                           end: calendar.date(byAdding: .day, value: 1, to: grid.weeks.last![6])!)
            : options.date.map {
                DateInterval(start: $0, end: calendar.date(byAdding: .day, value: options.days, to: $0)!)
            } ?? range(for: options.command, now: now, calendar: calendar)

        var events = fetch(store, interval)
        if options.command == .next {
            events = nextEvent(in: events, now: now).map { [$0] } ?? []
        }

        if options.json {
            print(try json(sorted(events)))
        } else if options.command == .week && terminalWidth() >= 64 {
            print(renderWeek(events, days: grid.weeks[0], now: now, width: terminalWidth(),
                             calendar: calendar, color: color, icons: icons,
                             work: workHours(ProcessInfo.processInfo.environment["CT_WORK"])))
        } else if options.command == .month && terminalWidth() >= 64 {
            print(renderGrid(events, anchor: grid.anchor, weeks: grid.weeks,
                             now: now, width: terminalWidth(), calendar: calendar, color: color, icons: icons))
        } else {
            // The first day to show; for `next`, the day of the event found.
            var first = interval.start
            if options.command == .next {
                first = calendar.startOfDay(for: max(events.first?.start ?? now, now))
            }
            let count = options.command == .week ? 7 : options.command == .next ? 1 : options.days
            let days = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first)! }
            if terminalWidth() >= 64 {
                print(renderTable(events, days: days, now: now, width: terminalWidth(),
                                  calendar: calendar, color: color, icons: icons))
            } else {
                print(render(events, from: calendar.startOfDay(for: first), calendar: calendar, color: color, icons: icons))
            }
        }
    }

    static func fetch(_ store: EKEventStore, _ interval: DateInterval) -> [Event] {
        let predicate = store.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: nil)
        return deduplicated(sorted(store.events(matching: predicate).map { item in
            sanitized(Event(
                title: item.title ?? "(no title)",
                start: item.startDate,
                end: item.endDate,
                isAllDay: item.isAllDay,
                calendar: item.calendar?.title ?? "",
                location: item.location,
                color: item.calendar.flatMap { hex($0.cgColor) },
                link: meetingLink(url: item.url?.absoluteString, location: item.location, notes: item.notes)))
        }))
    }

    static func hex(_ color: CGColor?) -> String? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = color?.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = rgb.components, parts.count >= 3 else { return nil }
        let value = parts.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", value[0], value[1], value[2])
    }

    static func terminalSize() -> (width: Int, height: Int) {
        var size = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0 {
            return (Int(size.ws_col), Int(size.ws_row))
        }
        return (ProcessInfo.processInfo.environment["COLUMNS"].flatMap { Int($0) } ?? 100, 30)
    }

    static func terminalWidth() -> Int { terminalSize().width }
}
