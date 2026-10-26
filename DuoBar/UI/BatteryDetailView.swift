import AppKit
import SwiftUI

/// The Battery side panel, modeled on the system Battery menu: power source,
/// Energy Mode, apps using significant energy, and Battery Settings.
struct BatteryDetailView: View {
    let battery: BatteryStatus
    let showPercentage: Bool
    let onOpenSettings: () -> Void

    @ObservedObject private var monitor = BatteryDetailMonitor.shared
    @State private var isChangingMode = false
    @State private var modeChangeFailed = false

    private var onBattery: Bool { !battery.isPluggedIn }
    private var energySettings: EnergyModeSettings? { monitor.energySettings }
    private var significantApps: [EnergyConsumer]? { monitor.significantApps }
    private var showsBrightness: Bool { monitor.showsBrightness }

    var body: some View {
        let batteryRow = BatteryStatusRow(battery: battery, showPercentage: showPercentage)

        VStack(alignment: .leading, spacing: 1) {
            ControlCenterSectionHeader(title: localized("Battery")) {
                if let percentage = batteryRow.trailingValue {
                    Text(percentage)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Group {
                Text(localized("Power Source: %@", onBattery ? localized("Battery") : localized("Power Adapter")))
                Text(batteryRow.detail)
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, ControlCenterMetrics.horizontalInset)
            .frame(minHeight: 20)

            if let energySettings {
                ControlCenterSeparator()
                ControlCenterSubheader(title: localized("Energy Mode"))
                ForEach(energySettings.availableModes) { mode in
                    ControlCenterDeviceRow(
                        symbol: mode.symbol,
                        title: mode.title,
                        isSelected: mode == energySettings.mode
                    ) {
                        select(mode, in: energySettings)
                    }
                    .disabled(isChangingMode)
                }
                if modeChangeFailed {
                    Text(localized("Unable to change Energy Mode"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, ControlCenterMetrics.horizontalInset)
                }
            }

            ControlCenterSeparator()
            ControlCenterSubheader(title: localized("Using Significant Energy"))
            significantEnergyRows

            ControlCenterSeparator()
            ControlCenterMenuItem(title: localized("Battery Settings…"), action: onOpenSettings)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: 280)
        .onAppear {
            monitor.refresh(onBattery: onBattery)
        }
        .onChange(of: onBattery) { newValue in
            monitor.refresh(onBattery: newValue, force: true)
        }
    }

    @ViewBuilder
    private var significantEnergyRows: some View {
        if showsBrightness {
            energyRow(icon: Image(systemName: "sun.max.fill"), title: localized("Display Brightness")) {
                _ = SystemSettingsOpener.open(.displays)
            }
        }
        if let significantApps {
            ForEach(significantApps) { app in
                energyRow(icon: appIcon(for: app.pid), title: app.name) {
                    NSRunningApplication(processIdentifier: app.pid)?.activate()
                }
            }
            if significantApps.isEmpty, !showsBrightness {
                Text(localized("No Apps Using Significant Energy"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ControlCenterMetrics.horizontalInset)
                    .frame(minHeight: 26)
            }
        } else {
            Text(localized("Checking…"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, ControlCenterMetrics.horizontalInset)
                .frame(minHeight: 26)
        }
    }

    private func energyRow(icon: Image, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .controlCenterRowChrome(minHeight: 26)
        }
        .buttonStyle(.plain)
    }

    private func appIcon(for pid: pid_t) -> Image {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            return Image(nsImage: icon)
        }
        return Image(systemName: "app")
    }

    private func select(_ mode: EnergyMode, in settings: EnergyModeSettings) {
        guard mode != settings.mode, !isChangingMode else { return }
        isChangingMode = true
        modeChangeFailed = false
        Task {
            modeChangeFailed = !(await monitor.setEnergyMode(mode, onBattery: onBattery))
            isChangingMode = false
        }
    }
}
