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
            .shadow(color: .black.opacity(0.11), radius: 20, x: 0, y: 9)
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

// MARK: - Weight-scale ruler slider — drag the ticks under a fixed needle

struct RulerSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var caption: String = ""
    var unit: String = ""
    var accent: Color = Theme.coral
    var tickSpacing: CGFloat = 14
    var showValue: Bool = true
    var showLabels: Bool = true

    @State private var anchor: Int? = nil   // value captured at drag start

    var body: some View {
        VStack(spacing: 10) {
            if showValue {
                if !caption.isEmpty {
                    Text(caption).font(Font2.sans(11, .bold)).tracking(2).foregroundStyle(Theme.ink.opacity(0.4))
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(value)")
                        .font(Font2.sans(58, .heavy)).foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: value)
                    if !unit.isEmpty {
                        Text(unit).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink.opacity(0.5))
                    }
                }
            }
            GeometryReader { geo in
                let mid = geo.size.width / 2
                Canvas { ctx, size in
                    for v in range {
                        let x = mid + CGFloat(v - value) * tickSpacing
                        guard x >= -2, x <= size.width + 2 else { continue }
                        let major = v % 5 == 0
                        let h: CGFloat = major ? 24 : 13
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 28))
                        p.addLine(to: CGPoint(x: x, y: 28 + h))
                        ctx.stroke(p, with: .color(Theme.ink.opacity(major ? 0.45 : 0.18)), lineWidth: major ? 2 : 1)
                        if major && showLabels {
                            ctx.draw(Text("\(v)").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.ink.opacity(0.4)),
                                     at: CGPoint(x: x, y: 64))
                        }
                    }
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3, height: 30).offset(y: 26)
                }
                .mask(LinearGradient(colors: [.clear, .black, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let base = anchor ?? value
                            if anchor == nil { anchor = value }
                            let delta = Int((g.translation.width / tickSpacing).rounded())
                            let nv = min(max(base - delta, range.lowerBound), range.upperBound)
                            if nv != value { value = nv; Haptics.select() }
                        }
                        .onEnded { _ in anchor = nil }
                )
            }
            .frame(height: showLabels ? 78 : 44)
        }
    }
}
