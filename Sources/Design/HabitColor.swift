import SwiftUI

/// Soft pastel palette for habit sticky-tiles and cards.
/// Deliberately only a few gentle hues — no saturated colors anywhere.
enum HabitColor: String, CaseIterable, Codable, Identifiable {
    case rose, berry, blush, amber, sage, sky, lilac, sand
    var id: String { rawValue }

    /// The single app palette = the 5 screen accent colors. One per case for cycling.
    static var palette: [HabitColor] { [.rose, .sky, .sage, .blush, .amber] }  // coral·periwinkle·sage·orchid·taupe

    /// Habits use the same 5 accent colors as the buttons (each a soft tint→accent gradient).
    /// The 8 case names alias onto these 5 so existing code keeps working.
    var stops: [Color] {
        switch self {
        case .rose, .berry:  return [Color(hex: "F2B3AB"), Color(hex: "E9887C")]   // coral
        case .sky:           return [Color(hex: "C9D6E9"), Color(hex: "ADC1DE")]   // periwinkle
        case .sage:          return [Color(hex: "C2D3B4"), Color(hex: "A6BA94")]   // sage
        case .blush, .lilac: return [Color(hex: "E3C2DC"), Color(hex: "D2A0C8")]   // orchid
        case .amber, .sand:  return [Color(hex: "C4B3A4"), Color(hex: "AA9281")]   // taupe
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Readable foreground (ink) on these gentle fills.
    var onColor: Color { Theme.ink.opacity(0.82) }
}
