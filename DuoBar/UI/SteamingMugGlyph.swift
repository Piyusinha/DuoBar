import AppKit
import SwiftUI

/// The SF Symbols steaming cup (`cup.and.heat.waves.fill`) with its steam
/// lifted a little above the rim. While `animates` is true the steam sways
/// gently, bending from its base like rising steam.
///
/// The symbol is cut once into two bitmaps at its rim: the cup (with the steam
/// and the steam's stubs inside the opening erased) and the steam alone. The
/// steam is drawn above the cup with a small gap. Cutting the symbol drawn in
/// one color keeps the rim solid where the steam used to cross it.
/// macOS 13 lacks the symbol and shows the plain cup instead.
struct SteamingMugGlyph: View {
    /// Overall height of the glyph, steam included.
    var height: CGFloat
    var animates = true

    @State private var swayed = false

    var body: some View {
        Group {
            if let pieces = Self.pieces {
                steamingCup(pieces)
            } else {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: height * 0.62, weight: .semibold))
            }
        }
        .frame(width: height, height: height, alignment: .bottom)
        .onAppear { startSway() }
        .onChange(of: animates) { _ in startSway() }
        .accessibilityHidden(true)
    }

    private func steamingCup(_ pieces: Pieces) -> some View {
        let symbolHeight = height * 0.9
        let size = CGSize(width: symbolHeight * Pieces.aspectRatio, height: symbolHeight)
        let steamHeight = size.height * Pieces.rimFraction
        let lift = height * 0.1

        return ZStack(alignment: .top) {
            Image(decorative: pieces.cup, scale: 1)
                .renderingMode(.template)
                .resizable()
                .frame(width: size.width, height: size.height)
                .offset(y: lift)

            Image(decorative: pieces.steam, scale: 1)
                .renderingMode(.template)
                .resizable()
                .frame(width: size.width, height: steamHeight)
                .modifier(SteamSway(amount: swayed ? 0.14 : -0.14))
        }
        .frame(width: size.width, height: size.height + lift, alignment: .top)
    }

    private func startSway() {
        guard animates else {
            withAnimation(nil) { swayed = false }
            return
        }
        swayed = false
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            swayed = true
        }
    }

    private static let pieces = Pieces.make()
}

/// The symbol cut into cup and steam bitmaps.
private struct Pieces {
    let cup: CGImage
    let steam: CGImage

    // Measured on the symbol at 100 pt semibold, a 131 × 126 image (rows from
    // the top): the steam sits above row 43, the rim's back edge spans rows
    // 44–53, and the steam's stubs inside the cup's opening fill x 37–78,
    // rows 54–62.
    static let aspectRatio: CGFloat = 131 / 126
    static let rimFraction: CGFloat = 43 / 126
    /// The steam keeps the rows above `steamBottomRow`; the cup keeps the rows
    /// from `rimTopRow` down. Row 43 belongs to neither: it holds only the
    /// anti-aliased seam where the steam meets the rim.
    private static let steamBottomRow: CGFloat = 43
    private static let rimTopRow: CGFloat = 44
    private static let stubs = CGRect(x: 37, y: 54, width: 38, height: 8)
    /// The right stub's edge reaches a little past `stubs`; the rim there
    /// starts one row lower, so this strip begins at row 55.
    private static let rightStubEdge = CGRect(x: 75, y: 55, width: 3, height: 7)

    static func make() -> Pieces? {
        guard #available(macOS 14.0, *),
              let symbol = NSImage(systemSymbolName: "cup.and.heat.waves.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 100, weight: .semibold))
        else { return nil }

        // 4× the point size: crisp at every menu bar icon scale.
        let scale: CGFloat = 4
        let width = Int(131 * scale)
        let height = Int(126 * scale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        symbol.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        let steamPixels = Int(steamBottomRow * scale)
        let rimPixels = Int(rimTopRow * scale)
        guard let full = context.makeImage(),
              // CGImage cropping counts rows from the top.
              let steam = full.cropping(to: CGRect(x: 0, y: 0, width: width, height: steamPixels))
        else { return nil }

        // CGContext counts rows from the bottom.
        context.clear(CGRect(x: 0, y: height - rimPixels, width: width, height: rimPixels))
        for rect in [stubs, rightStubEdge] {
            context.clear(CGRect(
                x: rect.minX * scale,
                y: CGFloat(height) - rect.maxY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            ))
        }
        guard let cup = context.makeImage() else { return nil }
        return Pieces(cup: cup, steam: steam)
    }
}

/// Shears the steam sideways around its bottom edge, so the wisps stay rooted
/// over the cup while their tops sway.
private struct SteamSway: GeometryEffect {
    var amount: CGFloat

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        // x' = x + amount * (height - y): still at the bottom, most at the top.
        ProjectionTransform(CGAffineTransform(a: 1, b: 0, c: -amount, d: 1, tx: amount * size.height, ty: 0))
    }
}
