import SwiftUI

/// A coffee mug with three wisps of steam floating a little above it. While
/// `animates` is true the steam gently jiggles side to side.
struct SteamingMugGlyph: View {
    /// Overall height of the glyph, steam included.
    var height: CGFloat
    var animates = true

    @State private var phase: CGFloat = 0

    var body: some View {
        let mugSize = height * 0.6
        ZStack(alignment: .bottom) {
            SteamShape(phase: phase)
                .stroke(style: StrokeStyle(lineWidth: max(1, height * 0.065), lineCap: .round))
                .frame(width: mugSize * 0.7, height: height * 0.3)
                // Wisps fade out as they rise.
                .mask(LinearGradient(colors: [.black.opacity(0.3), .black], startPoint: .top, endPoint: .bottom))
                // Centered over the mug body (left of the handle), lifted clear of the rim.
                .offset(x: -mugSize * 0.1, y: -(mugSize + height * 0.08))

            Image(systemName: "mug.fill")
                .font(.system(size: mugSize, weight: .semibold))
                .frame(height: mugSize)
        }
        .frame(width: height * 0.82, height: height, alignment: .bottom)
        .onAppear { startJiggle() }
        .onChange(of: animates) { _ in startJiggle() }
        .accessibilityHidden(true)
    }

    private func startJiggle() {
        guard animates else {
            withAnimation(nil) { phase = 0 }
            return
        }
        phase = 0
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

/// Three wavy wisps rising from the bottom edge. `phase` (0…1) slides the waves
/// along each wisp, which reads as steam jiggling as it rises.
private struct SteamShape: Shape {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let strands: [(x: CGFloat, heightScale: CGFloat, offset: CGFloat)] = [
            (0.15, 0.75, 0.0),
            (0.5, 1.0, 0.35),
            (0.85, 0.75, 0.7),
        ]
        let amplitude = rect.width * 0.065
        let steps = 16
        for strand in strands {
            let baseX = rect.minX + rect.width * strand.x
            let top = rect.maxY - rect.height * strand.heightScale
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let y = rect.maxY - (rect.maxY - top) * t
                // The wave grows toward the top, like steam spreading as it rises.
                let angle = (t * 0.9 - phase - strand.offset) * 2 * .pi
                let x = baseX + sin(angle) * amplitude * (0.35 + 0.65 * t)
                if step == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        return path
    }
}
