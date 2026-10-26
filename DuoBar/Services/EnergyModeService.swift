import AppKit
import Foundation

enum EnergyMode: Int, CaseIterable, Identifiable, Sendable {
    case automatic = 0
    case lowPower = 1
    case highPower = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .automatic: localized("Automatic")
        case .lowPower: localized("Low Power")
        case .highPower: localized("High Power")
        }
    }

    var symbol: String {
        switch self {
        case .automatic: "battery.100percent"
        case .lowPower: "battery.25percent"
        case .highPower: "gauge.with.dots.needle.100percent"
        }
    }
}

/// The Energy Mode settings for one power source, as `pmset -g custom` reports them.
struct EnergyModeSettings: Equatable, Sendable {
    /// `powermode` (Automatic / Low / High) on Macs with High Power Mode,
    /// `lowpowermode` (Automatic / Low) on the rest.
    enum Key: String, Sendable {
        case powerMode = "powermode"
        case lowPowerMode = "lowpowermode"
    }

    var key: Key
    var mode: EnergyMode

    var availableModes: [EnergyMode] {
        key == .powerMode ? EnergyMode.allCases : [.automatic, .lowPower]
    }

    /// Parses `pmset -g custom` output for the "Battery Power" or "AC Power" section.
    static func parse(pmsetCustomOutput output: String, onBattery: Bool) -> EnergyModeSettings? {
        let sectionTitle = onBattery ? "Battery Power:" : "AC Power:"
        var isInSection = false
        var lowPowerFallback: EnergyModeSettings?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(":") {
                isInSection = line == sectionTitle
                continue
            }
            guard isInSection else { continue }

            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, let value = Int(fields[1]) else { continue }
            switch String(fields[0]) {
            case Key.powerMode.rawValue:
                guard let mode = EnergyMode(rawValue: value) else { return nil }
                return EnergyModeSettings(key: .powerMode, mode: mode)
            case Key.lowPowerMode.rawValue:
                lowPowerFallback = EnergyModeSettings(key: .lowPowerMode, mode: value == 1 ? .lowPower : .automatic)
            default:
                continue
            }
        }
        return lowPowerFallback
    }

    /// `pmset` arguments that apply `mode` to the given power source.
    static func pmsetArguments(key: Key, mode: EnergyMode, onBattery: Bool) -> [String] {
        let value = key == .lowPowerMode ? (mode == .lowPower ? 1 : 0) : mode.rawValue
        return [onBattery ? "-b" : "-c", key.rawValue, String(value)]
    }
}

/// Reads and changes the system Energy Mode through `pmset`.
///
/// Reading needs no privileges. Changing does: DuoBar first tries a
/// non-interactive `sudo -n`. When that is not yet allowed, it asks macOS for
/// an administrator password once, applies the change, and installs a sudoers
/// rule that allows only the Energy Mode settings, so later changes need no
/// prompt.
enum EnergyModeService {
    private static let pmsetPath = "/usr/bin/pmset"
    static let sudoersRulePath = "/etc/sudoers.d/duobar-energy-mode"

    /// The sudoers rule: only `powermode` 0–2 and `lowpowermode` 0/1, on
    /// battery or adapter, for this user. Nil for names sudoers could misread.
    static func sudoersRule(for userName: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !userName.isEmpty,
              userName.first != "-",
              userName.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        let commands = [
            "\(pmsetPath) -b powermode [0-2]",
            "\(pmsetPath) -c powermode [0-2]",
            "\(pmsetPath) -b lowpowermode [01]",
            "\(pmsetPath) -c lowpowermode [01]",
        ]
        return "\(userName) ALL=(root) NOPASSWD: \(commands.joined(separator: ", "))"
    }

    /// Shell script run once with administrator privileges: installs the rule
    /// (only if `visudo` accepts it) and applies the requested change.
    static func privilegedScript(pmsetArguments: [String], userName: String) -> String {
        let apply = ([pmsetPath] + pmsetArguments).joined(separator: " ")
        guard let rule = sudoersRule(for: userName) else { return apply }
        let install = [
            "f=$(/usr/bin/mktemp /tmp/duobar-sudoers.XXXXXX)",
            "/usr/bin/printf '%s\\n' '# Lets DuoBar switch Energy Mode without a password prompt.' '\(rule)' > \"$f\"",
            "/usr/sbin/visudo -c -q -f \"$f\"",
            "/usr/bin/install -m 0440 -o root -g wheel \"$f\" \(sudoersRulePath)",
        ].joined(separator: " && ")
        // The rule is a convenience: the requested change is applied either way,
        // and its result decides success.
        return "{ \(install); }; /bin/rm -f \"$f\"; \(apply)"
    }

    /// Escapes text for use inside an AppleScript string literal.
    static func appleScriptLiteral(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func read(onBattery: Bool) async -> EnergyModeSettings? {
        await Task.detached(priority: .userInitiated) {
            guard let output = run(pmsetPath, ["-g", "custom"]) else { return nil }
            return EnergyModeSettings.parse(pmsetCustomOutput: output, onBattery: onBattery)
        }.value
    }

    /// Returns true when the change was applied.
    @MainActor
    static func set(_ mode: EnergyMode, key: EnergyModeSettings.Key, onBattery: Bool) async -> Bool {
        let arguments = EnergyModeSettings.pmsetArguments(key: key, mode: mode, onBattery: onBattery)

        let appliedWithoutPrompt = await Task.detached(priority: .userInitiated) {
            run("/usr/bin/sudo", ["-n", pmsetPath] + arguments) != nil
        }.value
        if appliedWithoutPrompt { return true }

        let script = privilegedScript(pmsetArguments: arguments, userName: NSUserName())
        let prompt = localized("Allow changing the Energy Mode. You won't be asked again.")
        let source = "do shell script \(appleScriptLiteral(script)) with administrator privileges with prompt \(appleScriptLiteral(prompt))"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    /// Runs a tool and returns its standard output, or nil when it fails.
    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
