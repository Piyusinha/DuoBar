import XCTest
@testable import DuoBar

final class EnergyModeTests: XCTestCase {
    private let highPowerMacOutput = """
    Battery Power:
     lowpowermode         0
     powermode            1
     sleep                1
    AC Power:
     powermode            2
     sleep                1
    """

    private let lowPowerOnlyOutput = """
    Battery Power:
     lowpowermode         1
    AC Power:
     lowpowermode         0
    """

    func testPowerModeIsReadForTheCurrentPowerSource() {
        XCTAssertEqual(
            EnergyModeSettings.parse(pmsetCustomOutput: highPowerMacOutput, onBattery: true),
            EnergyModeSettings(key: .powerMode, mode: .lowPower)
        )
        XCTAssertEqual(
            EnergyModeSettings.parse(pmsetCustomOutput: highPowerMacOutput, onBattery: false),
            EnergyModeSettings(key: .powerMode, mode: .highPower)
        )
    }

    func testMacsWithoutHighPowerModeOfferAutomaticAndLowPowerOnly() {
        let battery = EnergyModeSettings.parse(pmsetCustomOutput: lowPowerOnlyOutput, onBattery: true)
        XCTAssertEqual(battery, EnergyModeSettings(key: .lowPowerMode, mode: .lowPower))
        XCTAssertEqual(battery?.availableModes, [.automatic, .lowPower])

        let adapter = EnergyModeSettings.parse(pmsetCustomOutput: lowPowerOnlyOutput, onBattery: false)
        XCTAssertEqual(adapter?.mode, .automatic)
        XCTAssertEqual(
            EnergyModeSettings.parse(pmsetCustomOutput: highPowerMacOutput, onBattery: false)?.availableModes,
            [.automatic, .lowPower, .highPower]
        )
    }

    func testUnknownOrMissingValuesAreNotGuessed() {
        XCTAssertNil(EnergyModeSettings.parse(pmsetCustomOutput: "AC Power:\n powermode 7\n", onBattery: false))
        XCTAssertNil(EnergyModeSettings.parse(pmsetCustomOutput: "AC Power:\n sleep 1\n", onBattery: false))
        XCTAssertNil(EnergyModeSettings.parse(pmsetCustomOutput: "", onBattery: true))
    }

    func testPmsetArgumentsTargetTheCurrentPowerSource() {
        XCTAssertEqual(
            EnergyModeSettings.pmsetArguments(key: .powerMode, mode: .highPower, onBattery: false),
            ["-c", "powermode", "2"]
        )
        XCTAssertEqual(
            EnergyModeSettings.pmsetArguments(key: .lowPowerMode, mode: .lowPower, onBattery: true),
            ["-b", "lowpowermode", "1"]
        )
        XCTAssertEqual(
            EnergyModeSettings.pmsetArguments(key: .lowPowerMode, mode: .automatic, onBattery: true),
            ["-b", "lowpowermode", "0"]
        )
    }

    func testSudoersRuleAllowsOnlyEnergyModeSettings() throws {
        let rule = try XCTUnwrap(EnergyModeService.sudoersRule(for: "piyush.sinha"))
        XCTAssertEqual(
            rule,
            "piyush.sinha ALL=(root) NOPASSWD: /usr/bin/pmset -b powermode [0-2], /usr/bin/pmset -c powermode [0-2], "
                + "/usr/bin/pmset -b lowpowermode [01], /usr/bin/pmset -c lowpowermode [01]"
        )
        // visudo is what the install step runs before anything is written.
        XCTAssertEqual(try runTool("/usr/sbin/visudo", ["-c", "-q", "-f", writeTemporary(rule + "\n")]), 0)
    }

    func testSudoersRuleRejectsNamesSudoersCouldMisread() {
        for name in ["", "two words", "a,b", "a;b", "-flag", "a\nb", "ALL=(root)"] {
            XCTAssertNil(EnergyModeService.sudoersRule(for: name), name)
        }
    }

    func testPrivilegedScriptInstallsRuleThenAppliesTheChange() throws {
        let arguments = ["-c", "powermode", "1"]
        let script = EnergyModeService.privilegedScript(pmsetArguments: arguments, userName: "piyush")
        XCTAssertTrue(script.contains("/usr/sbin/visudo -c -q -f \"$f\""))
        XCTAssertTrue(script.contains(EnergyModeService.sudoersRulePath))
        XCTAssertTrue(script.hasSuffix("; /usr/bin/pmset -c powermode 1"))
        XCTAssertEqual(try runTool("/bin/sh", ["-n", "-c", script]), 0, "script must be valid shell")

        // Without a safe user name, only the change itself is applied.
        XCTAssertEqual(
            EnergyModeService.privilegedScript(pmsetArguments: arguments, userName: "bad name"),
            "/usr/bin/pmset -c powermode 1"
        )
    }

    func testPrivilegedScriptWritesARuleThatVisudoAccepts() throws {
        // Run the real script without privileges: copy instead of installing
        // into /etc/sudoers.d, and skip the pmset change.
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("duobar-rule-\(UUID().uuidString)").path
        let script = EnergyModeService.privilegedScript(pmsetArguments: ["-c", "powermode", "1"], userName: "piyush")
            .replacingOccurrences(of: "/usr/bin/install -m 0440 -o root -g wheel", with: "/bin/cp")
            .replacingOccurrences(of: EnergyModeService.sudoersRulePath, with: target)
            .replacingOccurrences(of: "; /usr/bin/pmset -c powermode 1", with: "; true")

        XCTAssertEqual(try runTool("/bin/sh", ["-c", script]), 0)
        let written = try String(contentsOfFile: target, encoding: .utf8)
        XCTAssertEqual(written, "# Lets DuoBar switch Energy Mode without a password prompt.\n"
            + EnergyModeService.sudoersRule(for: "piyush")! + "\n")
        XCTAssertEqual(try runTool("/usr/sbin/visudo", ["-c", "-q", "-f", target]), 0)
    }

    func testAppleScriptLiteralEscapesQuotesAndBackslashes() {
        XCTAssertEqual(EnergyModeService.appleScriptLiteral(#"say "hi" \n"#), #""say \"hi\" \\n""#)
    }

    private func writeTemporary(_ text: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("duobar-\(UUID().uuidString)")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func runTool(_ path: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func testEnergySampleUsesOnlyTheLastTopSample() {
        let output = """
        Processes: 600 total
        PID    POWER
        610    0.0
        16944  0.0

        Processes: 600 total
        PID    POWER
        610    45.9
        16944  11.1
        12970  6.6
        """
        XCTAssertEqual(EnergyImpactService.parse(topOutput: output), [
            .init(pid: 610, energyImpact: 45.9),
            .init(pid: 16944, energyImpact: 11.1),
            .init(pid: 12970, energyImpact: 6.6),
        ])
    }

    func testSignificantAppsCreditHelpersAndSkipSystemProcessesSelfAndLowImpact() {
        let samples: [EnergyImpactService.Sample] = [
            .init(pid: 610, energyImpact: 45.9),   // WindowServer: owned by no app
            .init(pid: 16944, energyImpact: 11.1), // Terminal Manager helper
            .init(pid: 16940, energyImpact: 1.0),  // Terminal Manager app
            .init(pid: 42, energyImpact: 30),      // DuoBar itself
            .init(pid: 12970, energyImpact: 6.6),  // below threshold on its own
            .init(pid: 500, energyImpact: 20),
        ]
        let owners: [pid_t: EnergyImpactService.OwningApp] = [
            16944: .init(pid: 16940, name: "Terminal Manager"),
            16940: .init(pid: 16940, name: "Terminal Manager"),
            42: .init(pid: 42, name: "DuoBar"),
            12970: .init(pid: 12970, name: "Chrome"),
            500: .init(pid: 500, name: "Safari"),
        ]
        let apps = EnergyImpactService.significant(samples, excluding: 42) { owners[$0] }

        XCTAssertEqual(apps.map(\.name), ["Safari", "Terminal Manager"])
        XCTAssertEqual(apps.last?.pid, 16940)
        XCTAssertEqual(apps.last?.energyImpact ?? 0, 12.1, accuracy: 0.001)
    }
}
