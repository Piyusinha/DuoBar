import SwiftUI

/// Building blocks for the Liquid Glass popover (macOS 26+). They mirror the
/// system Control Center modules: bold section titles, flat rows that highlight
/// on hover, circular device icons, and hairline separators between sections.
enum ControlCenterMetrics {
    static let horizontalInset: CGFloat = 8
    static let rowHeight: CGFloat = 34
    static let iconDiameter: CGFloat = 26
    static let highlightRadius: CGFloat = 7
}

struct ControlCenterSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, ControlCenterMetrics.horizontalInset)
        .frame(minHeight: 28)
    }
}

extension ControlCenterSectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

struct ControlCenterSubheader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, ControlCenterMetrics.horizontalInset)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
    }
}

struct ControlCenterSeparator: View {
    var body: some View {
        Divider()
            .padding(.horizontal, ControlCenterMetrics.horizontalInset)
            .padding(.vertical, 5)
    }
}

/// A device or connection row: circular icon, name, optional detail.
/// Selected rows use the accent-filled circle Control Center uses for the active device.
struct ControlCenterDeviceRow: View {
    let symbol: String
    let title: String
    var detail: String?
    var isSelected = false
    var showsDisclosure = false
    var accessibilityHint: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconForeground)
                    .frame(width: ControlCenterMetrics.iconDiameter, height: ControlCenterMetrics.iconDiameter)
                    .background(iconBackground, in: Circle())

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .controlCenterRowChrome(minHeight: detail == nil ? ControlCenterMetrics.rowHeight : 40)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(accessibilityHint ?? "")
    }

    // Control Center marks the active device with a white disc and accent glyph
    // in Dark Mode, and an accent disc with a white glyph in Light Mode.
    private var iconForeground: Color {
        guard isSelected else { return .primary }
        return colorScheme == .dark ? .accentColor : .white
    }

    private var iconBackground: AnyShapeStyle {
        guard isSelected else { return AnyShapeStyle(.primary.opacity(0.12)) }
        return colorScheme == .dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.accentColor)
    }
}

/// A plain text menu item such as "Sound Settings…".
struct ControlCenterMenuItem: View {
    let title: String
    var showsDisclosure = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ControlCenterMenuItemLabel(title: title, showsDisclosure: showsDisclosure)
        }
        .buttonStyle(.plain)
    }
}

struct ControlCenterMenuItemLabel: View {
    let title: String
    var showsDisclosure = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .controlCenterRowChrome(minHeight: 26)
    }
}

private struct ControlCenterRowChrome: ViewModifier {
    let minHeight: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ControlCenterMetrics.horizontalInset)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                .primary.opacity(isHovered ? 0.1 : 0),
                in: RoundedRectangle(cornerRadius: ControlCenterMetrics.highlightRadius, style: .continuous)
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    func controlCenterRowChrome(minHeight: CGFloat) -> some View {
        modifier(ControlCenterRowChrome(minHeight: minHeight))
    }
}

extension AudioDeviceStatus {
    /// Icon matching what Control Center shows for the device.
    var controlCenterSymbol: String {
        switch category {
        case .builtInSpeaker: return "laptopcomputer"
        case .airPods: return "airpodspro"
        case .headphones, .bluetoothAudio: return "headphones"
        case .displayAudio: return "display"
        case .usbAudio, .other: return "hifispeaker"
        }
    }

    var controlCenterInputSymbol: String {
        switch category {
        case .builtInSpeaker: return "laptopcomputer"
        case .airPods: return "airpodspro"
        case .headphones, .bluetoothAudio: return "headphones"
        case .displayAudio: return "display"
        case .usbAudio, .other: return "mic"
        }
    }
}
