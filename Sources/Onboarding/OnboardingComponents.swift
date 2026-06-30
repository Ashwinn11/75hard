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
/// `accentItalic` controls whether the accent word is italic (hero screens) or bold upright (quiz).
func serifAttr(_ lead: String, accent: String? = nil, trail: String? = nil,
               size: CGFloat = 34, accentColor: Color = Theme.rose, base: Color = Theme.ink,
               accentItalic: Bool = true) -> AttributedString {
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
    var accentItalic: Bool = true
    var alignment: TextAlignment = .leading

    var body: some View {
        TypewriterText(attributed: serifAttr(lead, accent: accent, trail: trail, size: size,
                                             accentColor: accentColor, accentItalic: accentItalic))
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

// MARK: - Photo marquee (welcome wall)

private struct MarqueeColumn: View {
    let names: [String]
    var up: Bool
    var speed: Double
    private let itemH: CGFloat = 150
    private let gap: CGFloat = 10
    @State private var offset: CGFloat = 0

    var body: some View {
        let loop = names + names
        VStack(spacing: gap) {
            ForEach(Array(loop.enumerated()), id: \.offset) { _, n in
                PhotoFill(name: n, fallback: gradientFor(n))
                    .frame(height: itemH).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .offset(y: offset)
        .onAppear {
            let total = (itemH + gap) * CGFloat(names.count)
            offset = up ? 0 : -total
            withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) { offset = up ? -total : 0 }
        }
    }
    private func gradientFor(_ n: String) -> LinearGradient {
        let palette: [HabitColor] = [.blush, .lilac, .sand, .sage, .rose, .sky]
        return palette[abs(n.hashValue) % palette.count].gradient
    }
}

struct PhotoMarquee: View {
    var names: [String] = (1...12).map { "onb_g\($0)" }
    var body: some View {
        let cols = stride(from: 0, to: names.count, by: 4).map { Array(names[$0..<min($0 + 4, names.count)]) }
        HStack(spacing: 10) {
            ForEach(Array(cols.enumerated()), id: \.offset) { i, col in
                MarqueeColumn(names: col, up: i % 2 == 0, speed: 22 + Double(i) * 4)
            }
        }
        .frame(maxWidth: .infinity)
        .mask(LinearGradient(colors: [.clear, .black, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
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
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { shownCount = i + 1 }
                        Haptics.tap()
                    }
                }
            }
    }
}

private struct FlowChips: View {
    let items: [(icon: String, text: String)]
    let shownCount: Int
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(rows().enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.0) { idx, item in
                        if idx < shownCount {
                            HStack(spacing: 6) {
                                Image(systemName: item.icon).font(.system(size: 13, weight: .bold))
                                Text(item.text).font(Font2.sans(15, .bold))
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(.white, in: Capsule())
                            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }
    private func rows() -> [[(Int, (icon: String, text: String))]] {
        var out: [[(Int, (icon: String, text: String))]] = []; var row: [(Int, (icon: String, text: String))] = []
        for (i, it) in items.enumerated() { row.append((i, it)); if row.count == 2 { out.append(row); row = [] } }
        if !row.isEmpty { out.append(row) }
        return out
    }
}

// MARK: - Track cluster (3 overlapping photos on a Choose-your-hard card)

struct TrackCluster: View {
    let prefix: String                 // e.g. "track_her" → track_her_1/2/3
    let colors: [HabitColor]
    var body: some View {
        HStack(spacing: -12) {
            ForEach(1...3, id: \.self) { i in
                PhotoFill(name: "\(prefix)_\(i)", fallback: colors[(i - 1) % colors.count].gradient)
                    .frame(width: 46, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 2))
                    .zIndex(Double(i))
            }
        }
    }
}

// MARK: - Edit-task sheet (sticky note + color swatches)

struct EditTaskSheet: View {
    @Binding var draft: HabitDraft
    var onSave: () -> Void
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Text("Edit task").font(Font2.serif(24, .semibold)).foregroundStyle(Theme.ink).padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                TextField("New daily task", text: $draft.title)
                    .font(Font2.sans(18, .bold)).foregroundStyle(Theme.ink)
                TextField("Add a note", text: $draft.subtitle)
                    .font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.7))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(draft.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 12) {
                ForEach(HabitColor.allCases) { c in
                    Circle().fill(c.gradient).frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Theme.ink, lineWidth: draft.color == c ? 2.5 : 0))
                        .onTapGesture { Haptics.select(); draft.color = c }
                }
            }

            HStack(spacing: 12) {
                if let onDelete {
                    Button { onDelete(); dismiss() } label: {
                        Text("Delete").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Theme.chipFill, in: Capsule())
                    }
                }
                Button { onSave(); dismiss() } label: {
                    Text("Save").font(Font2.sans(16, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.ink, in: Capsule())
                }
            }
            Spacer()
        }
        .padding(24)
        .presentationDetents([.height(380)])
        .her75Background()
    }
}

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

// MARK: - Mini phone preview (app-preview onboarding screen)

struct MiniPhonePreview: View {
    private let cards: [(String, HabitColor)] = [
        ("figure.run", .amber), ("drop.fill", .sage), ("book.fill", .sky), ("leaf.fill", .blush)
    ]
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Theme.roseGradient).frame(width: 26, height: 26)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: -1) {
                    Text("DAY 6").font(Font2.sans(9, .bold)).tracking(1).foregroundStyle(Theme.rose)
                    Text("Today").font(Font2.serif(15, .semibold)).foregroundStyle(Theme.ink)
                }
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.1.gradient)
                        .frame(height: 58)
                        .overlay(alignment: .bottomLeading) {
                            Text("task").font(Font2.sans(7, .bold)).foregroundStyle(Theme.ink.opacity(0.8))
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule()).padding(5)
                        }
                        .overlay(alignment: .topLeading) {
                            Image(systemName: c.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9)).padding(6)
                        }
                }
            }
            Spacer(minLength: 0)
            HStack { ForEach(0..<5) { i in Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(i == 0 ? Theme.rose : Theme.ink.opacity(0.25)) ; if i < 4 { Spacer() } } }
        }
        .padding(14)
        .frame(width: 200, height: 330)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.ink.opacity(0.85), lineWidth: 6))
        .shadow(color: .black.opacity(0.15), radius: 18, y: 10)
    }
}
