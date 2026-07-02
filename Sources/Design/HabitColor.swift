import SwiftUI

/// Soft pastel palette for habit sticky-tiles and cards.
/// Deliberately only a few gentle hues — no saturated colors anywhere.
enum HabitColor: String, CaseIterable, Codable, Identifiable {
    case rose, berry, blush, amber, sage, sky, lilac, sand
    var id: String { rawValue }

    /// The single app palette = the 5 screen accent colors. One per case for cycling.
    static var palette: [HabitColor] { [.rose, .sky, .sage, .blush, .amber] }  // clay·mist·olive·mauve·sand

    /// Habits use the same 5 accent colors as the buttons (each a soft tint→accent gradient).
    /// The 8 case names alias onto these 5 so existing code keeps working.
    var stops: [Color] {
        switch self {
        case .rose, .berry:  return [Color(hex: "DCA48E"), Color(hex: "C4765A")]   // clay
        case .sky:           return [Color(hex: "C0CDD3"), Color(hex: "94A8B1")]   // mist
        case .sage:          return [Color(hex: "B4BE9C"), Color(hex: "8D9A70")]   // olive (lightened for tiles)
        case .blush, .lilac: return [Color(hex: "C9ABB5"), Color(hex: "A98290")]   // mauve
        case .amber, .sand:  return [Color(hex: "D0BA9E"), Color(hex: "B69B7C")]   // sand
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Readable foreground (ink) on these gentle fills.
    var onColor: Color { Theme.ink.opacity(0.82) }
}
