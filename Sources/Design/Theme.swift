import SwiftUI

/// Design system: "porcelain & berry" — a cool lilac-white ground, deep plum ink, and a
/// single raspberry accent that owns every CTA. Supporting hues exist for tiles and
/// avatars only; they never color a button.
enum Theme {

    // MARK: Core
    static let paper     = Color(hex: "F5F3F7")   // background — cool porcelain
    static let cream     = paper                  // back-compat alias
    static let ink       = Color(hex: "262130")   // plum-charcoal — text + dark CTA

    // MARK: Brand accent (the one CTA color, everywhere)
    static let berry     = Color(hex: "A64D6D")   // raspberry
    static let berryDeep = Color(hex: "7E3651")
    static let berrySoft = Color(hex: "C98BA2")

    // MARK: Supporting hues (habit tiles, avatars, charts — never buttons)
    static let plum  = Color(hex: "9B84AE")
    static let slate = Color(hex: "8291AD")
    static let moss  = Color(hex: "6D8577")
    static let gold  = Color(hex: "B49B6C")

    // MARK: Back-compat aliases (the old per-screen accents now resolve into the new palette)
    static let rose     = berry
    static let clay     = berry
    static let clayDeep = berryDeep
    static let mist     = slate
    static let olive    = moss
    static let mauve    = plum
    static let sand     = gold

    // MARK: Surfaces / lines
    static let chipFill = Color(hex: "ECE8F0")
    static let ring     = Color(hex: "E1DCE7")

    // MARK: Semantic
    static let textSecondary = ink.opacity(0.5)

    // MARK: Gradients (kept subtle — surfaces are mostly flat)
    static let berryGradient = LinearGradient(colors: [berrySoft, berry], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let clayGradient  = berryGradient   // back-compat alias
    static let espressoGradient = LinearGradient(colors: [Color(hex: "342C40"), ink], startPoint: .top, endPoint: .bottom)

    // MARK: Metrics
    static let pillRadius: CGFloat = 18
    static let cardRadius: CGFloat = 26
}

// MARK: - App background

/// Paper that breathes: a near-imperceptible 3×3 mesh drifting between paper and a
/// whisper of the screen's accent, finished with a static grain so the fill reads as
/// actual paper instead of a flat hex. Meant to be felt, not seen.
struct AppBackground: View {
    var accent: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 10, paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate / 10
            let drift = Float(sin(t)) * 0.16
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + drift * 0.5, 0.5 - drift * 0.4], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: meshColors(warmth: 0.05 + Double(drift) * 0.06))
        }
        .colorEffect(ShaderLibrary.grain(.float(0.045)))
        .ignoresSafeArea()
    }

    private func meshColors(warmth: Double) -> [Color] {
        let tint = accent ?? Theme.plum
        let breath = Theme.paper.mix(with: tint, by: warmth)
        let corner = Theme.paper.mix(with: tint, by: 0.035)
        return [
            corner, Theme.paper, Theme.paper,
            Theme.paper, breath, Theme.paper,
            Theme.paper, Theme.paper, corner,
        ]
    }
}

extension View {
    func her75Background(_ accent: Color? = nil) -> some View { background(AppBackground(accent: accent)) }
}
