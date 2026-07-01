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

extension View {
    /// Caps a primary CTA to ~75% of the screen width, centered — matching the onboarding
    /// button treatment (`ctaPad`) so buttons feel consistent across the app.
    func ctaWidth() -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            self.containerRelativeFrame(.horizontal) { w, _ in w * 0.75 }
            Spacer(minLength: 0)
        }
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

// MARK: - Invite ticket (perforated coupon showing your name + join code)

/// Reused by onboarding's "invite your friends" screen and the Friends tab. `code` is nil while
/// the code is still being provisioned (shows a placeholder). The perforation notches are the page
/// background biting into a warm cream ticket.
struct InviteTicket: View {
    let name: String
    var code: String? = nil
    var compact: Bool = false            // show only the code half (no "Join <name>" header/perforation)
    var shareText: String? = nil         // when set, a share icon appears inline next to the code
    var ticketFill: Color = Color(hex: "F3EEE3")
    var notchColor: Color = Theme.paper  // should match the background behind the card

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                VStack(spacing: 10) {
                    Text("75 HER").font(Font2.sans(13, .bold)).tracking(5).foregroundStyle(Theme.ink.opacity(0.4))
                    (Text("Join ").font(Font2.serif(30, .semibold)).foregroundColor(Theme.ink)
                     + Text(name.isEmpty ? "me" : name).font(Font2.serif(30, .semibold)).italic().foregroundColor(Theme.ink)
                     + Text("\nfor the challenge").font(Font2.serif(30, .semibold)).foregroundColor(Theme.ink))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 26).padding(.top, 46).padding(.bottom, 30)

                perforation
            }

            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(code.map(SocialStore.format) ?? "•••• ••••")
                        .font(Font2.sans(34, .heavy)).tracking(4)
                        .foregroundStyle(code == nil ? Theme.ink.opacity(0.3) : Theme.ink)
                        .contentTransition(.opacity)

                    if let shareText, code != nil {
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.ink.opacity(0.55))
                                .frame(width: 32, height: 32)
                                .background(Theme.ink.opacity(0.08), in: Circle())
                        }
                        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                        .accessibilityLabel("Share your invite code")
                    }
                }
                Text("Share this code with your girls")
                    .font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.4))
            }
            .padding(.horizontal, 26).padding(.top, compact ? 34 : 28).padding(.bottom, compact ? 34 : 46)
        }
        .frame(maxWidth: .infinity)
        .background {
            // Shadow lives on the card shape only, so the notch circles (which poke past the
            // ticket edge) don't cast their own halos.
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(ticketFill)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        }
    }

    private var perforation: some View {
        ZStack {
            DashedRule().stroke(Theme.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 7]))
                .frame(height: 1.5).padding(.horizontal, 26)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading)  { notch.offset(x: -13) }
        .overlay(alignment: .trailing) { notch.offset(x: 13) }
    }

    private var notch: some View { Circle().fill(notchColor).frame(width: 26, height: 26) }
}

/// A single horizontal line through the middle of its rect (for dashed perforations).
struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
