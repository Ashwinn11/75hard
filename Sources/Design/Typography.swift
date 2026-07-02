import SwiftUI

/// Two-family type system:
/// • Cormorant Garamond — display serif; accent words are colored upright (no italic-accent pattern).
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

    private static func hankenName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return "HankenGrotesk-Regular"
        case .medium:                              return "HankenGrotesk-Medium"
        case .semibold, .bold:                     return "HankenGrotesk-Bold"
        default:                                   return "HankenGrotesk-ExtraBold" // heavy / black
        }
    }
}

// MARK: - Section / category title

/// The one serif header used above cards and field groups — Settings sections, Profile
/// categories, Add-friends groups. Defined once so every "category title" matches.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Font2.serif(22, .semibold))
            .foregroundStyle(Theme.ink)
    }
}

// MARK: - Serif headline with a colored accent word

/// Renders e.g. `SerifHeadline("Pick your", accent: "intensity")` →
/// "Pick your intensity" with the accent word in the screen's accent color
/// (upright — the italic-accent pattern is gone with the re-skin).
struct SerifHeadline: View {
    let lead: String
    var accent: String? = nil
    var trail: String? = nil
    var size: CGFloat = 40
    var color: Color = Theme.ink
    var accentColor: Color = Theme.clay
    var alignment: TextAlignment = .center

    var body: some View {
        var t = Text(lead).font(Font2.serif(size, .semibold)).foregroundColor(color)
        if let accent {
            t = t + Text(" ")
                + Text(accent).font(Font2.serif(size, .semibold)).foregroundColor(accentColor)
        }
        if let trail {
            t = t + Text(" ")
                + Text(trail).font(Font2.serif(size, .semibold)).foregroundColor(color)
        }
        return t.multilineTextAlignment(alignment)
    }
}

