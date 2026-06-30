import SwiftUI

/// A habit's color identity — a 2-stop gradient used by its sticky-note card and hive cells.
/// Tuned to the "1c — Feminine but loud" system: saturated, harmonized with rose/plum.
enum HabitColor: String, CaseIterable, Codable, Identifiable {
    case rose, berry, blush, amber, sage, sky, lilac, sand

    var id: String { rawValue }

    /// [light stop, deep stop] — top → bottom of the gradient.
    var stops: [Color] {
        switch self {
        case .rose:  return [Color(hex: "C24E57"), Color(hex: "9B3A52")]
        case .berry: return [Color(hex: "A33B63"), Color(hex: "6E2240")]
        case .blush: return [Color(hex: "F2A5AE"), Color(hex: "E07A89")]
        case .amber: return [Color(hex: "F0C36B"), Color(hex: "E0992F")]
        case .sage:  return [Color(hex: "A8C49C"), Color(hex: "7BA86E")]
        case .sky:   return [Color(hex: "A9C2E8"), Color(hex: "7C9FD6")]
        case .lilac: return [Color(hex: "CBA6E6"), Color(hex: "A87FD6")]
        case .sand:  return [Color(hex: "E7CBB0"), Color(hex: "D2A982")]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Readable foreground (ink) on these mid-saturation fills.
    var onColor: Color { Theme.ink.opacity(0.82) }
}
