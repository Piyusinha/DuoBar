import Combine
import Foundation

/// Keeps the Battery panel's Energy Mode and "Using Significant Energy" data
/// warm, so the panel opens with the last known values instead of a
/// "Checking…" placeholder and refreshes them quietly in the background.
@MainActor
final class BatteryDetailMonitor: ObservableObject {
    static let shared = BatteryDetailMonitor()

    @Published private(set) var energySettings: EnergyModeSettings?
    @Published private(set) var significantApps: [EnergyConsumer]?
    @Published private(set) var showsBrightness = false

    /// Brightness at or above this level is listed as a significant energy user.
    static let significantBrightness = 0.75

    private var refreshTask: Task<Void, Never>?
    private var lastRefresh: Date?
    private var lastPowerSourceWasBattery: Bool?

    /// Refreshes unless a refresh is running or one finished moments ago.
    func refresh(onBattery: Bool, force: Bool = false) {
        let powerSourceChanged = lastPowerSourceWasBattery != onBattery
        if !force, !powerSourceChanged {
            if refreshTask != nil { return }
            if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 5 { return }
        }
        refreshTask?.cancel()
        lastPowerSourceWasBattery = onBattery

        refreshTask = Task { [weak self] in
            let settings = await EnergyModeService.read(onBattery: onBattery)
            guard let self, !Task.isCancelled else { return }
            self.energySettings = settings
            if case .available(let brightness) = DisplayBrightnessService().readMainDisplay().availability {
                self.showsBrightness = brightness >= Self.significantBrightness
            }

            let apps = await EnergyImpactService.sampleSignificantApps()
            guard !Task.isCancelled else { return }
            self.significantApps = apps
            self.lastRefresh = Date()
            self.refreshTask = nil
        }
    }

    func setEnergyMode(_ mode: EnergyMode, onBattery: Bool) async -> Bool {
        guard let key = energySettings?.key else { return false }
        let applied = await EnergyModeService.set(mode, key: key, onBattery: onBattery)
        energySettings = await EnergyModeService.read(onBattery: onBattery)
        return applied
    }
}
