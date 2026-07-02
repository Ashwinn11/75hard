import SwiftUI

/// Design system: "soft luxe" — warm cream stationery, espresso ink, and one muted
/// earth accent per screen. Spa-morning energy (Aesop / Rituals), not candy pastels.
enum Theme {

    // MARK: Core
    static let paper     = Color(hex: "FAF6EF")   // background — warm cream
    static let cream     = paper                  // back-compat alias
    static let ink       = Color(hex: "2B2420")   // espresso — text + dark CTA

    // MARK: Per-screen earth accents
    static let clay  = Color(hex: "C4765A")       // welcome / partner — terracotta
    static let mist  = Color(hex: "94A8B1")       // app-preview / start — eucalyptus steam
    static let olive = Color(hex: "6E7B54")       // friends / length / promise
    static let mauve = Color(hex: "A98290")       // chips / quiz / custom — dusty rose
    static let sand  = Color(hex: "B69B7C")       // choose / ready — warm camel

    static let rose     = clay                    // back-compat: primary accent
    static let clayDeep = Color(hex: "AD5F43")    // deeper clay (avatar gradient)

    // MARK: Surfaces / lines
    static let chipFill = Color(hex: "F1EAE0")
    static let ring     = Color(hex: "E7DFD2")

    // MARK: Semantic
    static let textSecondary = ink.opacity(0.5)

    // MARK: Gradients (kept subtle — surfaces are mostly flat)
    static let clayGradient     = LinearGradient(colors: [clay, clayDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let espressoGradient = LinearGradient(colors: [Color(hex: "3C332C"), ink], startPoint: .top, endPoint: .bottom)

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
        let tint = accent ?? Theme.sand
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
