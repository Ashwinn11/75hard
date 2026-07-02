import SwiftUI

/// Design system = reproduce the reference screenshots exactly: soft, editorial, near-white
/// paper with one flat pastel accent per screen.
/// All hex values are sampled from the reference PNGs.
enum Theme {

    // MARK: Core
    static let paper     = Color(hex: "FDFCFB")   // background — warm near-white
    static let cream     = paper                  // back-compat alias
    static let ink       = Color(hex: "171717")   // text + dark CTA

    // MARK: Per-screen pastel accents
    static let coral      = Color(hex: "E9887C")  // welcome / partner
    static let periwinkle = Color(hex: "ADC1DE")  // app-preview / start / feedback
    static let sage       = Color(hex: "A6BA94")  // friends / length / promise
    static let orchid     = Color(hex: "D2A0C8")  // chips / quiz / custom
    static let taupe      = Color(hex: "AA9281")  // choose / ready

    static let rose      = coral                  // back-compat: primary accent
    static let roseDeep  = Color(hex: "E0746A")   // deeper coral (avatar gradient)

    // MARK: Surfaces / lines
    static let chipFill  = Color(hex: "F3F2F2")
    static let ring      = Color(hex: "ECE9E6")
    static let sageBadge = sage

    // MARK: Semantic
    static let textSecondary = ink.opacity(0.5)

    // MARK: Gradients (kept subtle — the reference is mostly flat color)
    static let roseGradient = LinearGradient(colors: [coral, roseDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let plumGradient = LinearGradient(colors: [Color(hex: "2A2A2E"), ink], startPoint: .top, endPoint: .bottom)

    // MARK: Metrics
    static let pillRadius: CGFloat = 30
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
        let tint = accent ?? Theme.taupe
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
