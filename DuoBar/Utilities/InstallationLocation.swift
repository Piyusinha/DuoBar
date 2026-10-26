import Foundation

/// Pure installation-location policy. UI and Finder interaction stay in AppDelegate.
enum InstallationLocation {
    static func isRunningFromDiskImage(bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.path.hasPrefix("/Volumes/")
    }

    static func isInstalledInApplications(bundleURL: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        let userApplications = homeDirectory.appendingPathComponent("Applications").standardizedFileURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    static func shouldOfferApplicationsHelp(bundleURL: URL, hasPresentedThisLaunch: Bool) -> Bool {
        !hasPresentedThisLaunch && isRunningFromDiskImage(bundleURL: bundleURL)
    }
}
