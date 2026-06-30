import SwiftUI

/// Design system = reproduce the reference screenshots exactly: soft, editorial, near-white
/// paper with one flat pastel accent per screen. (The honeycomb is our only addition.)
/// All hex values are sampled from the reference PNGs.
enum Theme {

    // MARK: Core
    static let paper     = Color(hex: "FDFCFB")   // background — warm near-white
    static let cream     = paper                  // back-compat alias
    static let ink       = Color(hex: "171717")   // text + dark CTA
    static let plum      = Color(hex: "242424")   // dark neutral surface (rare)

    // MARK: Per-screen pastel accents
    static let coral      = Color(hex: "E9887C")  // welcome / partner
    static let periwinkle = Color(hex: "ADC1DE")  // app-preview / start / feedback
    static let sage       = Color(hex: "A6BA94")  // friends / length / promise
    static let orchid     = Color(hex: "D2A0C8")  // chips / quiz / custom
    static let taupe      = Color(hex: "AA9281")  // choose / ready

    static let rose      = coral                  // back-compat: primary accent
    static let roseDeep  = Color(hex: "E0746A")
    static let pink      = Color(hex: "EBA5CA")    // soft pink (card / accents)

    // MARK: Custom-challenge card colors
    static let cardYellow = Color(hex: "EED796")
    static let cardGreen  = Color(hex: "D2E7A8")
    static let cardBlue   = Color(hex: "CADDF4")
    static let cardPink   = Color(hex: "EBA5CA")

    // MARK: Surfaces / lines
    static let chipFill  = Color(hex: "F3F2F2")
    static let ring      = Color(hex: "ECE9E6")
    static let sageBadge = sage

    // MARK: Semantic
    static let textPrimary   = ink
    static let textSecondary = ink.opacity(0.5)
    static let textOnRose    = Color.white

    // MARK: Gradients (kept subtle — the reference is mostly flat color)
    static let roseGradient = LinearGradient(colors: [coral, roseDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let plumGradient = LinearGradient(colors: [Color(hex: "2A2A2E"), ink], startPoint: .top, endPoint: .bottom)
    static let backdrop     = LinearGradient(colors: [paper, paper], startPoint: .top, endPoint: .bottom)

    // MARK: Metrics
    static let pillRadius: CGFloat = 30
    static let cardRadius: CGFloat = 26
    static let panelRadius: CGFloat = 34

    static func softShadow(_ color: Color = .black) -> Color { color.opacity(0.08) }
}

// MARK: - App background

struct AppBackground: View {
    var body: some View { Theme.paper.ignoresSafeArea() }
}

extension View {
    func her75Background() -> some View { background(AppBackground()) }
}
