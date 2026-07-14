import SwiftUI

// MARK: - Typewriter (reveals a styled AttributedString char-by-char, with haptic ticks)

struct TypewriterText: View {
    let attributed: AttributedString
    var speed: Double = 0.026
    var onDone: () -> Void = {}

    @State private var count = 0
    @State private var started = false

    var body: some View {
        Text(slice(count))
            .onAppear { run() }
    }

    private func slice(_ k: Int) -> AttributedString {
        let total = attributed.characters.count
        guard k < total else { return attributed }
        let end = attributed.index(attributed.startIndex, offsetByCharacters: max(0, k))
        return AttributedString(attributed[attributed.startIndex..<end])
    }

    private func run() {
        guard !started else { return }
        started = true
        let total = attributed.characters.count
        guard total > 0 else { onDone(); return }
        for k in 1...total {
            DispatchQueue.main.asyncAfter(deadline: .now() + speed * Double(k)) {
                count = k
                if k % 3 == 0 { Haptics.light() }
                if k == total { onDone() }
            }
        }
    }
}

/// Build a serif headline (with an accent word) as an AttributedString for the typewriter.
/// The accent word is colored, not italicized (the italic-accent pattern went with the re-skin);
/// `accentItalic` remains for the rare deliberately-italic line.
func serifAttr(_ lead: String, accent: String? = nil, trail: String? = nil,
               size: CGFloat = 34, accentColor: Color = Theme.berry, base: Color = Theme.ink,
               accentItalic: Bool = false) -> AttributedString {
    func run(_ s: String, italic: Bool, color: Color) -> AttributedString {
        var a = AttributedString(s)
        a.font = italic ? Font2.serif(size, .semibold).italic() : Font2.serif(size, .semibold)
        a.foregroundColor = color
        return a
    }
    var r = run(lead, italic: false, color: base)
    if let accent { r += run(" " + accent, italic: accentItalic, color: accentColor) }
    if let trail { r += run(" " + trail, italic: false, color: base) }
    return r
}

/// A typewriter serif headline used across onboarding.
struct TypewriterHeadline: View {
    let lead: String
    var accent: String? = nil
    var trail: String? = nil
    var size: CGFloat = 34
    var accentColor: Color = Theme.berry
    var accentItalic: Bool = false
    var alignment: TextAlignment = .leading

    var body: some View {
        TypewriterText(attributed: serifAttr(lead, accent: accent, trail: trail, size: size,
                                             accentColor: accentColor, accentItalic: accentItalic))
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

// MARK: - Dot calendar (welcome hero — 75 days as a filling grid, ending on a heart)

/// The signature welcome visual: a 5×15 grid of 75 dots that pop in one by one.
/// The first week fills berry (the journey starting), the final day is a small heart.
struct DotCalendar: View {
    var total: Int = 75
    @State private var beat = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 9), count: 15)

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 12) {
            ForEach(0..<total, id: \.self) { i in
                dot(i)
                    .frame(height: 11)
                    .popIn(delay: 0.2 + Double(i) * 0.012, from: 0.2)
            }
        }
        .onAppear {
            // Once the grid has landed, the goal-heart starts a soft ambient beat.
            guard !reduceMotion else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { beat = true }
        }
    }

    @ViewBuilder private func dot(_ i: Int) -> some View {
        if i == total - 1 {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.berry)
                .scaleEffect(beat ? 1.22 : 1)
                .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: beat)
        } else {
            Circle()
                .fill(i < 7 ? Theme.berry.opacity(0.85) : Theme.ink.opacity(0.12))
                .frame(width: 8, height: 8)
        }
    }
}

// EditTaskSheet lives in Sources/Components/UIComponents.swift — it's shared with Today's edit flow.

// MARK: - Signature pad (make-it-official step)

struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    @State private var current: [CGPoint] = []

    var body: some View {
        Canvas { ctx, _ in
            for stroke in strokes + [current] {
                var p = Path()
                if let f = stroke.first {
                    p.move(to: f); for pt in stroke.dropFirst() { p.addLine(to: pt) }
                }
                ctx.stroke(p, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .background(Color.white)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in current.append(v.location) }
                .onEnded { _ in strokes.append(current); current = []; Haptics.light() }
        )
    }
}

// MARK: - App screenshot (app-preview onboarding screen)

/// The real app screenshot (`Resources/Images/onb_preview.png`) shown in a phone frame.
/// The frame's aspect matches the screenshot (1170×2532) so nothing is cropped.
/// Full-device iPhone mockup around a real app screenshot — ported from yumeship's MockPhone
/// (Figma base 1280×2642, screen inset 55, radii 210/165). Titanium band is brand-tinted berry.
/// `onb_preview` already carries its own status bar, so no Dynamic Island is drawn over it.
struct AppScreenshot: View {
    var height: CGFloat = 430
    private let baseW: CGFloat = 1280, baseH: CGFloat = 2642

    private var width: CGFloat { height * baseW / baseH }
    private func r(_ n: CGFloat) -> CGFloat { n * width / baseW }

    var body: some View {
        ZStack {
            // Body
            RoundedRectangle(cornerRadius: r(210), style: .continuous).fill(Color(hex: "191521"))
            // Outer hairline
            RoundedRectangle(cornerRadius: r(210), style: .continuous)
                .strokeBorder(Color(hex: "6B3247"), lineWidth: max(1, r(5)))
            // Titanium band (brand berry)
            RoundedRectangle(cornerRadius: r(205), style: .continuous)
                .strokeBorder(Theme.berry, lineWidth: max(1, r(13))).padding(r(5))
            // Inner sheen
            RoundedRectangle(cornerRadius: r(200), style: .continuous)
                .strokeBorder(Color(hex: "CB93A8"), lineWidth: max(1, r(5))).padding(r(10)).opacity(0.9)
            // Bezel reflection
            RoundedRectangle(cornerRadius: r(187), style: .continuous)
                .strokeBorder(Color(hex: "68606E"), lineWidth: max(1, r(2))).padding(r(23)).opacity(0.8)
            // Screen
            Group {
                if AppImage.exists("onb_preview") { PhotoFill(name: "onb_preview") }
                else { Theme.chipFill }
            }
            .frame(width: width - 2 * r(55), height: height - 2 * r(55))
            .clipShape(RoundedRectangle(cornerRadius: r(165), style: .continuous))
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.22), radius: 24, y: 14)
        .rotationEffect(.degrees(-4))   // slight casual tilt
    }
}
