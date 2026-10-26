import Foundation

enum BatteryBoltPlacement: Equatable, Sendable {
    case none
    case topGap
}

enum BatteryRingColorRole: Equatable, Sendable {
    case monochrome
    case charging
    case lowPowerMode
    case lowBattery
}

struct BatteryRingPresentation: Equatable, Sendable {
    let boltPlacement: BatteryBoltPlacement
    let colorRole: BatteryRingColorRole
    /// True while the battery shows 100% with the charger still connected but the
    /// system has not yet reported the authoritative "fully charged" state.
    var boltDimmed: Bool = false

    static func resolve(
        battery: BatteryStatus,
        colorCodingEnabled: Bool
    ) -> BatteryRingPresentation {
        guard battery.isAvailable else {
            return BatteryRingPresentation(boltPlacement: .none, colorRole: .monochrome)
        }

        // IOPowerSources' authoritative full flag wins over a concurrent or
        // stale charging flag: fully charged never keeps green charging
        // semantics. The bolt stays while the adapter is connected, so the ring
        // still shows that the Mac is on power.
        if battery.isFullyCharged {
            return BatteryRingPresentation(
                boltPlacement: battery.isPluggedIn ? .topGap : .none,
                colorRole: .monochrome
            )
        }

        let boltPlacement: BatteryBoltPlacement = battery.isPluggedIn ? .topGap : .none
        let boltDimmed = boltPlacement == .topGap && (battery.percentage ?? 0) >= 100

        guard colorCodingEnabled else {
            return BatteryRingPresentation(
                boltPlacement: boltPlacement,
                colorRole: .monochrome,
                boltDimmed: boltDimmed
            )
        }

        let colorRole: BatteryRingColorRole
        if battery.isPluggedIn {
            colorRole = .charging
        } else if battery.isLowPowerModeEnabled {
            colorRole = .lowPowerMode
        } else if let percentage = battery.percentage, percentage < 20 {
            colorRole = .lowBattery
        } else {
            colorRole = .monochrome
        }
        return BatteryRingPresentation(
            boltPlacement: boltPlacement,
            colorRole: colorRole,
            boltDimmed: boltDimmed
        )
    }
}
