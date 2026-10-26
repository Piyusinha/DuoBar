import Foundation
import ServiceManagement
import XCTest
@testable import DuoBar

final class InstallationLocationTests: XCTestCase {
    func testMountedDiskImageBundleIsDetected() {
        let bundleURL = URL(fileURLWithPath: "/Volumes/DuoBar 1.3.0/DuoBar.app")
        XCTAssertTrue(InstallationLocation.isRunningFromDiskImage(bundleURL: bundleURL))
        XCTAssertTrue(InstallationLocation.shouldOfferApplicationsHelp(bundleURL: bundleURL, hasPresentedThisLaunch: false))
    }

    func testNonVolumeApplicationAndDevelopmentPathsDoNotPretendToBeDiskImages() {
        XCTAssertFalse(InstallationLocation.isRunningFromDiskImage(bundleURL: URL(fileURLWithPath: "/Applications/DuoBar.app")))
        XCTAssertFalse(InstallationLocation.isRunningFromDiskImage(bundleURL: URL(fileURLWithPath: "/Users/example/Applications/DuoBar.app")))
        XCTAssertFalse(InstallationLocation.isRunningFromDiskImage(bundleURL: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/DuoBar.app")))
        XCTAssertFalse(InstallationLocation.isRunningFromDiskImage(bundleURL: URL(fileURLWithPath: "/tmp/DerivedData/Build/Products/Debug/DuoBar.app")))
        XCTAssertFalse(InstallationLocation.isRunningFromDiskImage(bundleURL: URL(fileURLWithPath: "/VolumesBackup/DuoBar.app")))
    }

    func testApplicationsFoldersAreRecognizedAsInstalled() {
        let home = URL(fileURLWithPath: "/Users/example")
        XCTAssertTrue(InstallationLocation.isInstalledInApplications(bundleURL: URL(fileURLWithPath: "/Applications/DuoBar.app"), homeDirectory: home))
        XCTAssertTrue(InstallationLocation.isInstalledInApplications(bundleURL: URL(fileURLWithPath: "/Users/example/Applications/DuoBar.app"), homeDirectory: home))
        XCTAssertFalse(InstallationLocation.isInstalledInApplications(bundleURL: URL(fileURLWithPath: "/Volumes/DuoBar/DuoBar.app"), homeDirectory: home))
        XCTAssertFalse(InstallationLocation.isInstalledInApplications(bundleURL: URL(fileURLWithPath: "/tmp/DerivedData/Build/Products/Debug/DuoBar.app"), homeDirectory: home))
        XCTAssertFalse(InstallationLocation.isInstalledInApplications(bundleURL: URL(fileURLWithPath: "/ApplicationsBackup/DuoBar.app"), homeDirectory: home))
    }

    @MainActor
    func testLaunchAtLoginIsRegisteredWhenMissingAndLeftAloneOnceCurrent() {
        let defaults = UserDefaults(suiteName: "InstallationLocationTests.\(UUID().uuidString)")!
        let installed = URL(fileURLWithPath: "/Applications/DuoBar.app")
        var status = SMAppService.Status.notRegistered
        var registrations = 0

        for _ in 0..<3 {
            LaunchAtLoginService.ensureEnabledUnlessOptedOut(
                bundleURL: installed, buildIdentity: "8-100", defaults: defaults,
                status: { status }, register: { registrations += 1; status = .enabled }, unregister: {}
            )
        }

        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(defaults.string(forKey: PreferenceKeys.launchAtLoginRegisteredBuild), "8-100")
    }

    @MainActor
    func testLaunchAtLoginIsRefreshedWhenANewBuildIsInstalled() {
        let defaults = UserDefaults(suiteName: "InstallationLocationTests.\(UUID().uuidString)")!
        defaults.set("8-100", forKey: PreferenceKeys.launchAtLoginRegisteredBuild)
        var calls: [String] = []

        LaunchAtLoginService.ensureEnabledUnlessOptedOut(
            bundleURL: URL(fileURLWithPath: "/Applications/DuoBar.app"), buildIdentity: "8-200", defaults: defaults,
            status: { .enabled }, register: { calls.append("register") }, unregister: { calls.append("unregister") }
        )

        XCTAssertEqual(calls, ["unregister", "register"])
        XCTAssertEqual(defaults.string(forKey: PreferenceKeys.launchAtLoginRegisteredBuild), "8-200")
    }

    @MainActor
    func testLaunchAtLoginRespectsOptOutApprovalAndInstallLocation() {
        let defaults = UserDefaults(suiteName: "InstallationLocationTests.\(UUID().uuidString)")!
        var registrations = 0
        let register = { registrations += 1 }

        LaunchAtLoginService.ensureEnabledUnlessOptedOut(
            bundleURL: URL(fileURLWithPath: "/tmp/DerivedData/Build/Products/Release/DuoBar.app"), buildIdentity: "1",
            defaults: defaults, status: { .notRegistered }, register: register, unregister: {}
        )
        LaunchAtLoginService.ensureEnabledUnlessOptedOut(
            bundleURL: URL(fileURLWithPath: "/Applications/DuoBar.app"), buildIdentity: "1",
            defaults: defaults, status: { .requiresApproval }, register: register, unregister: {}
        )
        defaults.set(true, forKey: PreferenceKeys.launchAtLoginOptedOut)
        LaunchAtLoginService.ensureEnabledUnlessOptedOut(
            bundleURL: URL(fileURLWithPath: "/Applications/DuoBar.app"), buildIdentity: "1",
            defaults: defaults, status: { .notRegistered }, register: register, unregister: {}
        )

        XCTAssertEqual(registrations, 0)
    }

    func testPromptIsOncePerLaunchDecision() {
        let bundleURL = URL(fileURLWithPath: "/Volumes/DuoBar/DuoBar.app")
        XCTAssertFalse(InstallationLocation.shouldOfferApplicationsHelp(bundleURL: bundleURL, hasPresentedThisLaunch: true))
    }
}
