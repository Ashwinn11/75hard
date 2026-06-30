import SwiftUI

// MARK: - Primary pill button (chunky, 30px radius)

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = Theme.coral          // per-screen flat pastel accent
    var textColor: Color = .white
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)) }
                Text(title).font(Font2.sans(17, .bold))
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(color, in: RoundedRectangle(cornerRadius: Theme.pillRadius, style: .continuous))
            .shadow(color: color.opacity(0.30), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Ink (near-black) high-emphasis variant — used for "Save" / "Become Her".
extension PrimaryButton {
    static func ink(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> PrimaryButton {
        PrimaryButton(title: title, icon: icon, color: Theme.ink, textColor: .white, action: action)
    }
}

// MARK: - Chip

struct Chip: View {
    let text: String
    var emoji: String? = nil
    var filled: Bool = true
    var body: some View {
        HStack(spacing: 6) {
            if let emoji { Text(emoji).font(.system(size: 14)) }
            Text(text).font(Font2.sans(14, .bold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule().fill(filled ? Theme.chipFill : Color.white)
        }
        .overlay {
            if !filled { Capsule().stroke(Theme.ring, lineWidth: 1.5) }
        }
    }
}

// MARK: - Thin progress bar (white on rose)

struct ProgressBarThin: View {
    var value: Double                 // 0…1
    var track: Color = .white.opacity(0.30)
    var fill: Color = .white
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: max(height, geo.size.width * value))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Soft white card

struct SoftCard: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func softCard(padding: CGFloat = 18) -> some View {
        modifier(SoftCard(padding: padding))
    }
}

// MARK: - Press feedback

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
