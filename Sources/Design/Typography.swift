import SwiftUI

/// Two-family type system:
/// • Cormorant Garamond — display serif, big headlines with italic accent words.
/// • Hanken Grotesk — UI/body sans at heavy weights for titles, buttons, eyebrow labels.
enum Font2 {

    // MARK: Serif (Cormorant Garamond, variable — weight via SwiftUI .weight())
    static let serifFamily = "Cormorant Garamond"

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        Font.custom(serifFamily, size: size).weight(weight)
    }

    // MARK: Sans (Hanken Grotesk — static instances, addressed by PostScript name)
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.custom(hankenName(weight), fixedSize: size)
    }

    /// Hanken at a size that still scales with Dynamic Type, relative to a text style.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .bold, relativeTo style: Font.TextStyle) -> Font {
        Font.custom(hankenName(weight), size: size, relativeTo: style)
    }

    private static func hankenName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return "HankenGrotesk-Regular"
        case .medium:                              return "HankenGrotesk-Medium"
        case .semibold, .bold:                     return "HankenGrotesk-Bold"
        default:                                   return "HankenGrotesk-ExtraBold" // heavy / black
        }
    }
}

// MARK: - Eyebrow label  ("MAX EFFORT", "DAY 12 · 75 HARD")

struct EyebrowLabel: View {
    let text: String
    var color: Color = Theme.rose
    var body: some View {
        Text(text.uppercased())
            .font(Font2.sans(12, .bold))
            .tracking(2.2)                       // wide letterspacing
            .foregroundStyle(color)
    }
}

// MARK: - Serif headline with a pink italic accent word

/// Renders e.g. `SerifHeadline("Pick your", accent: "intensity")` →
/// "Pick your *intensity*" with the accent word in italic pink.
struct SerifHeadline: View {
    let lead: String
    var accent: String? = nil
    var trail: String? = nil
    var size: CGFloat = 40
    var color: Color = Theme.ink
    var accentColor: Color = Theme.coral
    var alignment: TextAlignment = .center

    var body: some View {
        var t = Text(lead).font(Font2.serif(size, .semibold)).foregroundColor(color)
        if let accent {
            t = t + Text(" ")
                + Text(accent).font(Font2.serif(size, .semibold)).italic().foregroundColor(accentColor)
        }
        if let trail {
            t = t + Text(" ")
                + Text(trail).font(Font2.serif(size, .semibold)).foregroundColor(color)
        }
        return t.multilineTextAlignment(alignment)
    }
}

// MARK: - Convenience text modifiers

extension Text {
    func serifDisplay(_ size: CGFloat = 40, weight: Font.Weight = .semibold, color: Color = Theme.ink) -> some View {
        self.font(Font2.serif(size, weight)).foregroundStyle(color)
    }
    func sansTitle(_ size: CGFloat = 18, weight: Font.Weight = .bold, color: Color = Theme.ink) -> some View {
        self.font(Font2.sans(size, weight)).foregroundStyle(color)
    }
}
