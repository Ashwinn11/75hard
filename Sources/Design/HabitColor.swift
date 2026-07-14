import SwiftUI

/// Soft palette for habit sticky-tiles and cards, derived from the porcelain-&-berry
/// system. Deliberately only a few gentle hues — no saturated colors anywhere.
enum HabitColor: String, CaseIterable, Codable, Identifiable {
    case rose, berry, blush, amber, sage, sky, lilac, sand
    var id: String { rawValue }

    /// The single app palette = the 5 supporting tile hues. One per case for cycling.
    static var palette: [HabitColor] { [.rose, .sky, .sage, .blush, .amber] }  // berry·slate·moss·plum·gold

    /// Habits use tile tints of the app palette (each a soft tint→hue gradient).
    /// The 8 case names alias onto these 5 so existing code keeps working.
    var stops: [Color] {
        switch self {
        case .rose, .berry:  return [Color(hex: "D9A5B6"), Color(hex: "BC7089")]   // berry
        case .sky:           return [Color(hex: "B7C2D6"), Color(hex: "8FA0BC")]   // slate
        case .sage:          return [Color(hex: "AFC2B4"), Color(hex: "84A18F")]   // moss
        case .blush, .lilac: return [Color(hex: "C7B9D8"), Color(hex: "A791C1")]   // plum
        case .amber, .sand:  return [Color(hex: "D6C29B"), Color(hex: "B49B6C")]   // gold
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Readable foreground (ink) on these gentle fills.
    var onColor: Color { Theme.ink.opacity(0.82) }
}
