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
               size: CGFloat = 34, accentColor: Color = Theme.rose, base: Color = Theme.ink,
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
    var accentColor: Color = Theme.rose
    var accentItalic: Bool = false
    var alignment: TextAlignment = .leading

    var body: some View {
        TypewriterText(attributed: serifAttr(lead, accent: accent, trail: trail, size: size,
                                             accentColor: accentColor, accentItalic: accentItalic))
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

// MARK: - Photo marquee (welcome wall)

private struct MarqueeRow: View {
    let names: [String]
    var leftward: Bool
    var speed: Double
    private let tileW: CGFloat = 120
    private var tileH: CGFloat { tileW * 4 / 3 }     // locked 3:4 portrait
    private let gap: CGFloat = 10
    @State private var offset: CGFloat = 0

    var body: some View {
        let loop = names + names                     // two sets → seamless wrap
        // Color.clear is flexible — it returns the proposed width, not the natural
        // HStack width (~3900 pt). This prevents MarqueeRow from inflating the parent
        // VStack beyond screen bounds. The HStack lives in an overlay so it never
        // contributes to layout size.
        Color.clear
            .frame(height: tileH)
            .overlay(alignment: .leading) {
                HStack(spacing: gap) {
                    ForEach(Array(loop.enumerated()), id: \.offset) { _, n in
                        PhotoFill(name: n, fallback: gradientFor(n))
                            .frame(width: tileW, height: tileH)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .offset(x: offset)
            }
            .clipped()
            .onAppear {
                let total = (tileW + gap) * CGFloat(names.count)
                offset = leftward ? 0 : -total
                withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) { offset = leftward ? -total : 0 }
            }
    }
    private func gradientFor(_ n: String) -> LinearGradient {
        let palette: [HabitColor] = [.blush, .lilac, .sand, .sage, .rose, .sky]
        // Deterministic hash (String.hashValue is randomized per launch — colors would reshuffle).
        var h = 5381
        for b in n.utf8 { h = (h &* 33) &+ Int(b) }
        return palette[abs(h) % palette.count].gradient
    }
}

/// A horizontal photo wall: two rows of 3:4 tiles drifting in opposite directions.
struct PhotoMarquee: View {
    var names: [String] = (1...15).map { "onb_g\($0)" }
    var body: some View {
        let rows = split(names, into: 2)
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                MarqueeRow(names: row, leftward: i % 2 == 0, speed: 18 + Double(i) * 6)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .mask(LinearGradient(colors: [.clear, .black, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
    }
    private func split(_ names: [String], into count: Int) -> [[String]] {
        var rows = Array(repeating: [String](), count: count)
        for (i, n) in names.enumerated() { rows[i % count].append(n) }
        return rows
    }
}

// MARK: - Option pill (quiz)

struct OptionPill: View {
    let text: String
    let selected: Bool
    var action: () -> Void
    var body: some View {
        Button { Haptics.select(); action() } label: {
            HStack(spacing: 10) {
                if selected { Circle().fill(Theme.ink).frame(width: 8, height: 8) }
                Text(text).font(Font2.sans(17, .bold)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 22).padding(.vertical, 17)        // hugs its content width
            .background(.ultraThinMaterial, in: Capsule())          // native blur
            .background(selected ? Theme.chipFill.opacity(0.6) : .clear, in: Capsule())
            .overlay(Capsule().stroke(selected ? Theme.rose : Color.white.opacity(0.7), lineWidth: selected ? 2 : 1))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Animated chips (appear one by one)

struct AnimatedChips: View {
    let items: [(icon: String, text: String)]
    @State private var shownCount = 0
    var body: some View {
        FlowChips(items: items, shownCount: shownCount)
            .onAppear {
                for i in 0..<items.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Double(i + 1)) {
                        withAnimation(Motion.bouncy) { shownCount = i + 1 }
                        Haptics.tap()
                    }
                }
            }
    }
}

private struct FlowChips: View {
    let items: [(icon: String, text: String)]
    let shownCount: Int

    // Scatter the chips around the photo's edges so the subject in the center stays clear.
    private let spots: [(alignment: Alignment, offset: CGSize)] = [
        (.topLeading,     CGSize(width:  6, height:  16)),
        (.topTrailing,    CGSize(width: -6, height:  46)),
        (.bottomLeading,  CGSize(width: 10, height: -30)),
        (.bottomTrailing, CGSize(width: -8, height: -16)),
        (.bottom,         CGSize(width: 24, height: -96)),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i < shownCount {
                    let spot = spots[i % spots.count]
                    FloatingPill(hPad: 15, vPad: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon).font(.system(size: 13, weight: .bold))
                            Text(item.text).font(Font2.sans(15, .bold))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: spot.alignment)
                    .offset(spot.offset)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(18)
    }
}

// EditTaskSheet lives in Sources/Components/UIComponents.swift — it's shared with Today's edit flow.

// MARK: - Signature pad (sign your promise)

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
struct AppScreenshot: View {
    var height: CGFloat = 430
    private let aspect: CGFloat = 1170.0 / 2532.0

    var body: some View {
        Group {
            if AppImage.exists("onb_preview") {
                PhotoFill(name: "onb_preview")
            } else {
                Theme.chipFill
            }
        }
        .frame(width: height * aspect, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Theme.ink.opacity(0.85), lineWidth: 6))
        .shadow(color: .black.opacity(0.15), radius: 18, y: 10)
    }
}
