import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    /// Keeps Launch at Login on unless the user switched it off in Settings.
    ///
    /// Runs on every launch from an Applications folder. The login item is
    /// registered when it is missing, and re-registered when a different build
    /// is installed, so the system record follows the app that is actually on
    /// disk instead of a replaced build's signature.
    static func ensureEnabledUnlessOptedOut(
        bundleURL: URL = Bundle.main.bundleURL,
        buildIdentity: String? = currentBuildIdentity(),
        defaults: UserDefaults = .standard,
        status: () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: () throws -> Void = { try SMAppService.mainApp.unregister() }
    ) {
        guard !defaults.bool(forKey: PreferenceKeys.launchAtLoginOptedOut) else { return }
        guard InstallationLocation.isInstalledInApplications(bundleURL: bundleURL) else { return }

        let currentStatus = status()
        // Waiting on the user in System Settings; registering again cannot help.
        guard currentStatus != .requiresApproval else { return }

        let registeredBuild = defaults.string(forKey: PreferenceKeys.launchAtLoginRegisteredBuild)
        if currentStatus == .enabled, registeredBuild == buildIdentity { return }

        do {
            if currentStatus == .enabled {
                try? unregister()
            }
            try register()
            defaults.set(buildIdentity, forKey: PreferenceKeys.launchAtLoginRegisteredBuild)
        } catch {
            #if DEBUG
            NSLog("[DuoBar] launch-at-login registration failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Changes whenever a new build replaces the installed app.
    nonisolated static func currentBuildIdentity(bundle: Bundle = .main) -> String? {
        guard let executableURL = bundle.executableURL,
              let modified = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version)-\(Int(modified.timeIntervalSince1970))"
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        UserDefaults.standard.set(!enabled, forKey: PreferenceKeys.launchAtLoginOptedOut)

        do {
            if enabled {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(Self.currentBuildIdentity(), forKey: PreferenceKeys.launchAtLoginRegisteredBuild)
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh()
    }
}
