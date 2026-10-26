import SwiftUI

struct NearbyWiFiButton: View {
    let statusStore: SystemStatusStore
    let onOpenSettings: () -> Void
    /// Control Center style: a plain menu item instead of a compact card.
    var controlCenterStyle = false

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            if controlCenterStyle {
                ControlCenterMenuItemLabel(title: localized("Nearby Networks"), showsDisclosure: true)
            } else {
                HStack(spacing: 8) {
                    Label(localized("Nearby Networks"), systemImage: "wifi")
                        .font(.system(size: 10.5, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .frame(height: 28)
                .duoRowBackground(cornerRadius: 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(localized("Browse nearby Wi-Fi networks"))
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            NearbyWiFiPopoverView(
                statusStore: statusStore,
                onOpenSettings: {
                    isPresented = false
                    onOpenSettings()
                }
            )
        }
    }
}

private struct NearbyWiFiPopoverView: View {
    let statusStore: SystemStatusStore
    let onOpenSettings: () -> Void

    @ObservedObject private var controller: NearbyWiFiController

    init(statusStore: SystemStatusStore, onOpenSettings: @escaping () -> Void) {
        self.statusStore = statusStore
        self.onOpenSettings = onOpenSettings
        controller = statusStore.nearbyWiFiController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localized("Nearby Networks"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                if controller.state == .scanning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(localized("Scanning…"))
                }
            }

            Divider()

            content

            Divider()

            HStack {
                Button {
                    Task { await statusStore.refreshNearbyWiFi() }
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(controller.isBusy || controller.isWiFiPoweredOn == false)

                Spacer()

                Button(localized("Network Settings…"), action: onOpenSettings)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 300)
        .task {
            await statusStore.scanNearbyWiFiIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if controller.isWiFiPoweredOn == false {
            message(localized("Wi-Fi is Off"), symbol: "wifi.slash")
        } else if controller.state == .scanning && controller.networks.isEmpty {
            message(localized("Scanning…"), symbol: "wifi")
        } else if case let .failure(error) = controller.state, controller.networks.isEmpty {
            message(error, symbol: "exclamationmark.triangle")
        } else if controller.networks.isEmpty {
            VStack(spacing: 8) {
                if locationAccessIsRestricted {
                    message(
                        localized("Location access is needed to show Wi-Fi network names."),
                        symbol: "location.slash"
                    )
                    Button(localized("Open System Settings…")) {
                        _ = SystemSettingsOpener.open(.privacy)
                    }
                    .controlSize(.small)
                } else {
                    message(localized("No Networks Found"), symbol: "wifi.slash")
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(controller.networks) { network in
                        networkButton(network)
                    }
                }
            }
            .frame(maxHeight: 252)

            if case let .failure(error) = controller.state {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 76)
    }

    private func networkButton(_ network: NearbyWiFiNetwork) -> some View {
        Button {
            select(network)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: network.signalSymbolName, variableValue: network.signalSymbolVariableValue)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(network.ssid)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if network.security != .open {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(localized("Secured network"))
                }

                if network.isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityLabel(localized("Current Network"))
                } else if isJoining(network) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(localized("Joining…"))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .frame(height: 30)
        .disabled(network.isCurrent || controller.isBusy)
        .accessibilityLabel(network.ssid)
        .accessibilityValue(accessibilityValue(for: network))
        .accessibilityHint(network.isCurrent ? localized("Current Network") : localized("Join network"))
    }

    private func select(_ network: NearbyWiFiNetwork) {
        guard !network.isCurrent else { return }
        controller.clearTransientState()

        switch network.security {
        case .open:
            Task { _ = await statusStore.joinNearbyWiFi(network, password: nil) }
        case .personal:
            askForPassword(to: network, errorMessage: nil, password: "")
        case .enterprise, .unsupported:
            onOpenSettings()
        }
    }

    private func isJoining(_ network: NearbyWiFiNetwork) -> Bool {
        controller.state == .joining(networkID: network.id)
    }

    /// Shows the password alert, joins, and asks again with the reason and the
    /// typed password kept when joining fails, like the system prompt.
    private func askForPassword(to network: NearbyWiFiNetwork, errorMessage: String?, password: String) {
        // Let the row click finish before the modal alert takes over.
        DispatchQueue.main.async {
            guard let entered = WiFiPasswordPrompt.ask(
                ssid: network.ssid,
                errorMessage: errorMessage,
                password: password
            ) else {
                controller.clearTransientState()
                return
            }
            guard !entered.isEmpty else {
                askForPassword(to: network, errorMessage: nil, password: "")
                return
            }
            Task {
                let joined = await statusStore.joinNearbyWiFi(network, password: entered)
                guard !joined, case let .failure(message) = controller.state else { return }
                askForPassword(to: network, errorMessage: message, password: entered)
            }
        }
    }

    private var locationAccessIsRestricted: Bool {
        let authorization = statusStore.wifiSSIDAuthorization
        return authorization == .denied || authorization == .restricted
    }

    private func accessibilityValue(for network: NearbyWiFiNetwork) -> String {
        let strength: String
        switch network.signalLevel {
        case .strong: strength = localized("Strong signal")
        case .medium: strength = localized("Medium signal")
        case .weak: strength = localized("Weak signal")
        case .disconnected, .disabled, .unavailable: strength = localized("Signal unavailable")
        }
        return network.isCurrent
            ? "\(localized("Current Network")), \(strength)"
            : strength
    }
}
