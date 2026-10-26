import AppKit

/// The Wi-Fi password dialog, presented as a standard alert window like the
/// system "requires a password" prompt: Wi-Fi icon, network name, password
/// field with Show Password, and Join / Cancel.
@MainActor
enum WiFiPasswordPrompt {
    /// Returns the entered password, or nil when the user cancels.
    static func ask(ssid: String, errorMessage: String?, password: String) -> String? {
        let (alert, fields) = makeAlert(ssid: ssid, errorMessage: errorMessage, password: password)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return fields.password
    }

    static func makeAlert(ssid: String, errorMessage: String?, password: String) -> (NSAlert, PasswordFields) {
        let alert = NSAlert()
        alert.messageText = localized("The Wi-Fi network “%@” requires a password.", ssid)
        alert.informativeText = errorMessage ?? localized("Enter the password to join this network.")
        alert.icon = icon
        alert.addButton(withTitle: localized("Join"))
        alert.addButton(withTitle: localized("Cancel"))

        let fields = PasswordFields(password: password)
        alert.accessoryView = fields.view
        alert.window.initialFirstResponder = fields.secureField
        return (alert, fields)
    }

    private static var icon: NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 44, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor]))
        return NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

/// Password field with a "Show password" checkbox that swaps in a plain field.
@MainActor
final class PasswordFields: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 52))
    let secureField = NSSecureTextField(frame: NSRect(x: 0, y: 28, width: 260, height: 22))
    private let plainField = NSTextField(frame: NSRect(x: 0, y: 28, width: 260, height: 22))
    private let showPassword = NSButton(checkboxWithTitle: localized("Show password"), target: nil, action: nil)

    var password: String {
        showPassword.state == .on ? plainField.stringValue : secureField.stringValue
    }

    init(password: String) {
        super.init()
        for field in [secureField, plainField] {
            field.stringValue = password
            field.placeholderString = localized("Password")
            field.setAccessibilityLabel(localized("Password"))
            view.addSubview(field)
        }
        plainField.isHidden = true

        showPassword.frame = NSRect(x: 0, y: 0, width: 260, height: 20)
        showPassword.target = self
        showPassword.action = #selector(toggleShowPassword)
        view.addSubview(showPassword)
    }

    @objc private func toggleShowPassword() {
        let revealing = showPassword.state == .on
        let (from, to): (NSTextField, NSTextField) = revealing ? (secureField, plainField) : (plainField, secureField)
        to.stringValue = from.stringValue
        from.isHidden = true
        to.isHidden = false
        to.window?.makeFirstResponder(to)
    }
}
