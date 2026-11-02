import SwiftUI

/// Popover controls for Keep Awake: an on/off switch, duration chips
/// (5m, 10m, 30m, 1h, ∞), and a countdown while a timed session runs.
struct KeepAwakeSection: View {
    @ObservedObject var keepAwake: KeepAwakeService
    /// Liquid Glass (macOS 26+) layout when true; the card layout otherwise.
    var controlCenterStyle = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            chips
            if let session = keepAwake.session {
                statusLine(for: session)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if controlCenterStyle {
            ControlCenterSectionHeader(title: localized("Keep Awake")) { toggle }
        } else {
            HStack(spacing: 11) {
                Image(systemName: keepAwake.isActive ? KeepAwakeSymbol.active : KeepAwakeSymbol.inactive)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .duoIconBackground(.primary.opacity(0.12))
                Text(localized("Keep Awake"))
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 8)
                toggle
            }
        }
    }

    private var toggle: some View {
        Toggle(localized("Keep Awake"), isOn: Binding(
            get: { keepAwake.isActive },
            set: { isOn in
                if isOn {
                    keepAwake.start(.indefinitely)
                } else {
                    keepAwake.stop()
                }
            }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(controlCenterStyle ? .small : .mini)
        .accessibilityLabel(localized("Keep Awake"))
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(KeepAwakeDuration.allCases) { duration in
                KeepAwakeChip(
                    title: duration.shortTitle,
                    isSelected: keepAwake.session?.duration == duration
                ) {
                    if keepAwake.session?.duration == duration {
                        keepAwake.stop()
                    } else {
                        keepAwake.start(duration)
                    }
                }
                .accessibilityLabel(localized("Keep awake for %@", duration.accessibilityTitle))
            }
        }
        .padding(.horizontal, ControlCenterMetrics.horizontalInset)
    }

    private func statusLine(for session: KeepAwakeSession) -> some View {
        HStack(spacing: 6) {
            SteamingMugGlyph(height: 14, animates: !reduceMotion)
                .foregroundStyle(Color.accentColor)
            if let endDate = session.endDate {
                Text(localized("Awake until %@", endDate.formatted(date: .omitted, time: .shortened)))
                Spacer(minLength: 6)
                Text(timerInterval: Date()...max(Date(), endDate), countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            } else {
                Text(localized("Awake until turned off"))
                Spacer(minLength: 6)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, ControlCenterMetrics.horizontalInset)
        .frame(minHeight: 20)
    }
}

private struct KeepAwakeChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(background, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.primary.opacity(isHovered ? 0.16 : 0.1))
    }
}
