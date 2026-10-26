import AppKit
import Foundation

struct EnergyConsumer: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let energyImpact: Double
    var id: pid_t { pid }
}

/// Approximates the Battery menu's "Using Significant Energy" list from a short
/// `top` energy-impact sample. Only regular apps are listed; system daemons,
/// helpers, and DuoBar itself are left out, as in the system menu.
enum EnergyImpactService {
    /// Apps at or above this energy impact count as significant.
    static let significantThreshold = 10.0
    static let maximumListed = 5

    struct Sample: Equatable {
        let pid: pid_t
        let energyImpact: Double
    }

    /// Parses `top -l 2 -stats pid,power` output. The first sample has no
    /// interval to measure against, so only the last one is used.
    static func parse(topOutput output: String) -> [Sample] {
        var samples: [Sample] = []
        for rawLine in output.split(separator: "\n") {
            let fields = rawLine.split(whereSeparator: \.isWhitespace)
            if fields.first == "PID" {
                samples.removeAll()
                continue
            }
            guard fields.count >= 2,
                  let pid = pid_t(fields[0]),
                  let impact = Double(fields[fields.count - 1])
            else { continue }
            samples.append(Sample(pid: pid, energyImpact: impact))
        }
        return samples
    }

    struct OwningApp: Equatable {
        let pid: pid_t
        let name: String
    }

    /// Credits each sampled process to the app that owns it (helpers count
    /// toward their parent app, as in the system menu), then keeps apps whose
    /// combined impact is significant.
    static func significant(
        _ samples: [Sample],
        excluding ownPID: pid_t,
        owningApp: (pid_t) -> OwningApp?
    ) -> [EnergyConsumer] {
        var totals: [pid_t: (name: String, impact: Double)] = [:]
        for sample in samples {
            guard let app = owningApp(sample.pid), app.pid != ownPID else { continue }
            totals[app.pid, default: (app.name, 0)].impact += sample.energyImpact
        }
        return totals
            .filter { $0.value.impact >= significantThreshold }
            .map { EnergyConsumer(pid: $0.key, name: $0.value.name, energyImpact: $0.value.impact) }
            .sorted { $0.energyImpact > $1.energyImpact }
            .prefix(maximumListed)
            .map { $0 }
    }

    /// Walks up the parent chain until it reaches a running app.
    @MainActor
    static func owningApp(for pid: pid_t) -> OwningApp? {
        var current = pid
        for _ in 0..<8 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.activationPolicy != .prohibited,
               let name = app.localizedName {
                return OwningApp(pid: current, name: name)
            }
            guard let parent = parentPID(of: current) else { return nil }
            current = parent
        }
        return nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        // launchd (1) owns every top-level process, so stop there.
        return parent > 1 ? parent : nil
    }

    static func sampleSignificantApps() async -> [EnergyConsumer] {
        let output = await Task.detached(priority: .utility) { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
            process.arguments = ["-l", "2", "-s", "1", "-stats", "pid,power", "-o", "power", "-n", "20"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value

        guard let output else { return [] }
        return await MainActor.run {
            significant(
                parse(topOutput: output),
                excluding: ProcessInfo.processInfo.processIdentifier,
                owningApp: owningApp(for:)
            )
        }
    }
}
