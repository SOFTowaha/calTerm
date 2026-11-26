import AppKit
import CalTermCore
import EventKit
import Foundation

nonisolated(unsafe) private var stopRequested: sig_atomic_t = 0

/// Runs the full-screen interface until the user quits.
func runInterface(store: EKEventStore, color: Bool, icons: Bool) {
    guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
        fail("ui needs an interactive terminal", code: 64)
    }
    var original = termios()
    tcgetattr(STDIN_FILENO, &original)
    var raw = original
    cfmakeraw(&raw)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    for number in [SIGTERM, SIGHUP] { signal(number) { _ in stopRequested = 1 } }

    func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
    // Alternate screen, hidden cursor, no line wrapping.
    write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?7l")
    defer {
        write("\u{1B}[?7h\u{1B}[?25h\u{1B}[?1049l")
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    }

    var app = App(now: Date(), calendar: .current)
    app.icons = icons
    var loaded: DateInterval?
    func load() {
        loaded = app.window
        app.events = CalTerm.fetch(store, app.window)
    }
    load()

    var previous = ""
    while stopRequested == 0 {
        app.now = Date()
        let size = CalTerm.terminalSize()
        let screen = app.frame(width: size.width, height: size.height, color: color)
            .joined(separator: "\u{1B}[K\r\n")
        if screen != previous {
            write("\u{1B}[H" + screen + "\u{1B}[J")
            previous = screen
        }

        // Wake regularly to follow window resizes and keep the countdown current.
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        if poll(&descriptor, 1, 250) <= 0 { continue }
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        if count <= 0 { break }

        for key in decodeKeys(Array(buffer.prefix(count))) {
            switch app.handle(key) {
            case .quit:
                return
            case .reload:
                if app.message == "Refreshed" || app.window != loaded { load() }
            case .open(let link):
                if let url = URL(string: link), url.scheme == "https" { NSWorkspace.shared.open(url) }
            case .none:
                break
            }
        }
    }
}
