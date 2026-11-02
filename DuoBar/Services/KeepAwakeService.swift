import AppKit
import Combine
import Foundation

/// How long Keep Awake holds the Mac awake.
enum KeepAwakeDuration: Hashable, Identifiable, CaseIterable, Sendable {
    case fiveMinutes
    case tenMinutes
    case thirtyMinutes
    case oneHour
    case indefinitely

    var id: Self { self }

    /// Seconds to stay awake, or nil to stay awake until turned off.
    var seconds: Int? {
        switch self {
        case .fiveMinutes: 5 * 60
        case .tenMinutes: 10 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .indefinitely: nil
        }
    }

    /// Compact label for the duration chips.
    var shortTitle: String {
        switch self {
        case .fiveMinutes: localized("5m")
        case .tenMinutes: localized("10m")
        case .thirtyMinutes: localized("30m")
        case .oneHour: localized("1h")
        case .indefinitely: "∞"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .fiveMinutes: localized("5 minutes")
        case .tenMinutes: localized("10 minutes")
        case .thirtyMinutes: localized("30 minutes")
        case .oneHour: localized("1 hour")
        case .indefinitely: localized("Until turned off")
        }
    }
}

enum KeepAwakeSymbol {
    /// A steaming cup while Keep Awake runs (SF Symbols 5, macOS 14+), with the
    /// plain cup as the macOS 13 fallback.
    static var active: String {
        if #available(macOS 14.0, *) { return "cup.and.heat.waves.fill" }
        return "cup.and.saucer.fill"
    }

    static let inactive = "cup.and.saucer"
}

struct KeepAwakeSession: Equatable, Sendable {
    let duration: KeepAwakeDuration
    let startDate: Date

    /// When the session ends on its own; nil when it runs until turned off.
    var endDate: Date? {
        duration.seconds.map { startDate.addingTimeInterval(TimeInterval($0)) }
    }
}

/// Keeps the Mac and its display awake with Apple's `caffeinate` tool, the same
/// approach KeepingYouAwake uses. No privileges are needed.
///
/// `caffeinate` is started with `-w <DuoBar's pid>`, so it exits on its own if
/// DuoBar quits or crashes and the Mac is never left awake by accident.
@MainActor
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()

    @Published private(set) var session: KeepAwakeSession?

    private static let caffeinatePath = "/usr/bin/caffeinate"
    private var process: Process?

    var isActive: Bool { session != nil }

    /// Arguments for `caffeinate`: `-d` keeps the display on, `-i` prevents idle
    /// system sleep, `-t` ends after the duration, and `-w` ties it to DuoBar.
    nonisolated static func caffeinateArguments(for duration: KeepAwakeDuration, watchingProcess pid: Int32) -> [String] {
        var arguments = ["-di"]
        if let seconds = duration.seconds {
            arguments += ["-t", String(seconds)]
        }
        arguments += ["-w", String(pid)]
        return arguments
    }

    /// Starts keeping the Mac awake, replacing any session already running.
    func start(_ duration: KeepAwakeDuration, now: Date = Date()) {
        terminateProcess()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.caffeinatePath)
        process.arguments = Self.caffeinateArguments(
            for: duration,
            watchingProcess: ProcessInfo.processInfo.processIdentifier
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.processDidExit(finished)
            }
        }

        do {
            try process.run()
        } catch {
            NSLog("[DuoBar] Keep Awake could not start caffeinate: %@", error.localizedDescription)
            session = nil
            return
        }

        self.process = process
        session = KeepAwakeSession(duration: duration, startDate: now)
    }

    /// Lets the Mac sleep normally again.
    func stop() {
        terminateProcess()
        session = nil
    }

    private func terminateProcess() {
        guard let process else { return }
        self.process = nil
        // Clear the handler first so the old process can't end a newer session.
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    /// Called when `caffeinate` exits on its own, normally because its timer ran out.
    private func processDidExit(_ finished: Process) {
        guard finished === process else { return }
        process = nil
        session = nil
    }
}
