import SwiftUI

// MARK: - Primary button (chunky rounded rect, one brand accent everywhere)

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = Theme.berry         // the single CTA color — override only for dark/ink variants
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
        }
        .buttonStyle(PillPressStyle(color: color))
    }
}

/// The pill background + shadow live in the style so a press physically "sits the
/// button down" — scale dips while the shadow compresses under it — and releases
/// with a bounce.
struct PillPressStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(color, in: RoundedRectangle(cornerRadius: Theme.pillRadius, style: .continuous))
            .shadow(color: color.opacity(configuration.isPressed ? 0.16 : 0.30),
                    radius: configuration.isPressed ? 4 : 10, x: 0, y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(Motion.bouncy, value: configuration.isPressed)
    }
}

extension View {
    /// Primary CTAs span their container's full width — matching the onboarding
    /// button treatment (`ctaPad`) so buttons feel consistent across the app.
    func ctaWidth() -> some View {
        frame(maxWidth: .infinity)
    }
}

// MARK: - Circular icon button (44pt, white) — the tab-header action style

struct CircleIconButton: View {
    let icon: String
    var action: () -> Void
    var body: some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44).background(.white, in: Circle())
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Profile avatar (the user's photo, or the rose placeholder) in a white-ringed circle

struct ProfileAvatar: View {
    var size: CGFloat = 66
    @AppStorage("profilePhotoV") private var photoVersion = 0
    @State private var sweep: Double = 0        // one-shot rose sweep around the ring on photo change

    var body: some View {
        ZStack {
            if let img = ProfilePhoto.load() {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.clayGradient
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .id(photoVersion)
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: max(2, size / 44)))
        .overlay {
            if sweep > 0 {
                Circle()
                    .stroke(AngularGradient(colors: [.clear, Theme.clay, Theme.clayDeep, .clear],
                                            center: .center),
                            lineWidth: max(2, size / 44))
                    .rotationEffect(.degrees(sweep))
                    .opacity(sweep < 360 ? 1 : 0)
            }
        }
        .shadow(color: .black.opacity(0.10), radius: size / 9, y: size / 18)
        .onChange(of: photoVersion) {
            sweep = 1
            withAnimation(.easeInOut(duration: 0.8)) { sweep = 360 }
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
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.bouncy, value: configuration.isPressed)
    }
}

// MARK: - Weight-scale ruler slider — drag the ticks under a fixed needle

struct RulerSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var caption: String = ""
    var unit: String = ""
    var accent: Color = Theme.clay
    var tickSpacing: CGFloat = 14
    var showValue: Bool = true
    var showLabels: Bool = true

    @State private var anchor: Int? = nil   // value captured at drag start
    @State private var overshoot: CGFloat = 0   // rubber-band px past the range ends
    @State private var dragging = false
    @State private var flingTask: Task<Void, Never>? = nil

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
                .offset(x: overshoot)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3, height: 30)
                        .scaleEffect(dragging ? 1.2 : 1)
                        .shadow(color: accent.opacity(dragging ? 0.7 : 0), radius: dragging ? 5 : 0)
                        .animation(Motion.snappy, value: dragging)
                        .offset(y: 26)
                }
                .mask(LinearGradient(colors: [.clear, .black, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            flingTask?.cancel()
                            if anchor == nil { anchor = value; dragging = true }
                            let base = anchor ?? value
                            let delta = Int((g.translation.width / tickSpacing).rounded())
                            let raw = base - delta
                            let nv = min(max(raw, range.lowerBound), range.upperBound)
                            // Rubber-band: past the ends the ticks keep following the
                            // finger at 0.3× resistance instead of pinning dead.
                            overshoot = max(-44, min(44, CGFloat(nv - raw) * tickSpacing * 0.3))
                            if nv != value { value = nv; Haptics.select() }
                        }
                        .onEnded { g in
                            anchor = nil; dragging = false
                            withAnimation(Motion.bouncy) { overshoot = 0 }
                            fling(velocity: g.predictedEndTranslation.width - g.translation.width)
                        }
                )
            }
            .frame(height: showLabels ? 78 : 44)
        }
    }

    /// Momentum: a flick keeps ticking with exponential decay, one haptic per tick.
    private func fling(velocity: CGFloat) {
        let ticks = Int((abs(velocity) / (tickSpacing * 6)).rounded())
        guard ticks > 0 else { return }
        let step = velocity > 0 ? -1 : 1        // dragging right lowers the value
        flingTask = Task { @MainActor in
            var interval = 0.028
            for _ in 0..<min(ticks, 30) {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                interval *= 1.16
                let nv = min(max(value + step, range.lowerBound), range.upperBound)
                guard nv != value else { return }
                value = nv
                Haptics.select()
            }
        }
    }
}

// MARK: - Floating pill (the frosted badge used across the app)

/// The one small floating badge — a frosted `.ultraThinMaterial` capsule with a soft shadow.
/// Used for taglines/counts on the welcome, partner, invite, and challenge-card screens, plus
/// the Today day pill. Frosted (not plain white) so it blurs whatever sits behind it.
struct FloatingPill<Content: View>: View {
    var hPad: CGFloat = 14
    var vPad: CGFloat = 8
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, hPad).padding(.vertical, vPad)
            .background {
                // Frosted blur + a slight white wash so it reads a touch more solid.
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(.white.opacity(0.6))
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 7, y: 3)
    }
}

// MARK: - Challenge photo-strip card (4 photos + floating pill + title)

/// The one challenge card used everywhere — onboarding's library, the profile card, and the
/// switch-challenge flow — so a track always shows the same photos and fallback colors.
struct ChallengeStripCard: View {
    let track: ChallengeTrack
    var pillText: String? = nil      // override for the floating pill; nil → the track's tagline
    var pillIcon: String = "checkmark"   // icon beside an overridden pill text
    var showTitle = true             // callers whose pill already names the challenge pass false

    private var pill: String? { pillText ?? (track.tagline.isEmpty ? nil : track.tagline) }

    // Deterministic palette seed (String.hashValue is randomized per launch).
    private var seed: Int {
        var h = 5381
        for b in track.rawValue.utf8 { h = (h &* 33) &+ Int(b) }
        return abs(h)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .top) {
                // Color.clear locks the row to the CONTAINER width at aspect n×(3/4); inside,
                // GeometryReader gives us that width so each cell is an EXPLICIT, identical
                // W/4 × W/3 box — provably equal and exactly 3:4 (no flexible-frame guessing).
                Color.clear
                    .aspectRatio(CGFloat(track.photos.count) * 3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            let n = CGFloat(track.photos.count)
                            let gap: CGFloat = 3
                            let cellW = (geo.size.width - gap * (n - 1)) / n
                            HStack(spacing: gap) {
                                ForEach(Array(track.photos.enumerated()), id: \.offset) { i, p in
                                    PhotoFill(name: p, fallback: HabitColor.palette[(seed + i) % HabitColor.palette.count].gradient)
                                        .frame(width: cellW, height: geo.size.height)
                                        .clipped()
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if let pill {
                    FloatingPill(hPad: 10, vPad: 5) {
                        HStack(spacing: 5) {
                            if pillText != nil {
                                Image(systemName: pillIcon).font(.system(size: 10, weight: .heavy))
                            }
                            Text(pill).font(Font2.sans(11, .bold))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .offset(y: -11)   // float above the top edge, horizontally centered
                }
            }
            if showTitle {
                Text(track.title).font(Font2.serif(22, .semibold)).foregroundStyle(Theme.ink)
            }
        }
    }
}

// MARK: - Editable task list (photo strip + "Create Daily Task +" + numbered sticky rows)

/// Shared by onboarding's challenge detail (over HabitDrafts) and Today's edit sheet (over live
/// Habits). Display + taps only — the owner supplies add/edit behavior and its own edit sheet.
struct TaskListEditor: View {
    let track: ChallengeTrack
    let items: [(title: String, color: HabitColor)]
    var onAdd: () -> Void
    var onEdit: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChallengeStripCard(track: track, showTitle: false)
            Button { onAdd() } label: {
                Text("Create Daily Task +").font(Font2.sans(15, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .ctaWidth()
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    row(i, item).staggeredAppear(index: i)
                    if i < items.count - 1 { Divider().padding(.leading, 62) }
                }
            }
        }
    }

    // The "sticky paper" number-tile rows — the soft shadow gives the lifted sticky-note feel.
    private func row(_ i: Int, _ item: (title: String, color: HabitColor)) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(item.color.gradient)
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 4)
                Text("\(i + 1)").font(Font2.serif(24, .medium)).italic().foregroundStyle(Theme.ink.opacity(0.8))
            }
            Text(item.title).font(Font2.sans(15, .bold)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { onEdit(i) } label: {
                Image(systemName: "pencil").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink.opacity(0.55))
                    .frame(width: 30, height: 30).background(Theme.chipFill, in: Circle())
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Edit-task sheet (sticky note + color swatches) — edits a HabitDraft binding

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
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .background(draft.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .animation(Motion.gentle, value: draft.color)

            HStack(spacing: 12) {
                ForEach(HabitColor.palette) { c in
                    Circle().fill(c.gradient).frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Theme.ink, lineWidth: draft.color == c ? 2.5 : 0))
                        .scaleEffect(draft.color == c ? 1.18 : 1)
                        .animation(Motion.pop, value: draft.color)
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
        .presentationDetents([.height(340)])
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - Option row (the app's one selectable-choice card — quiz answers, durations)

/// A full-width white card with a trailing radio-check. Selection fills the check berry
/// and draws an accent border. Optional `note` (small sub-line) and `badge` (tiny tag).
struct OptionRow: View {
    let title: String
    var note: String? = nil
    var badge: String? = nil
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button { Haptics.select(); action() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
                        if let badge {
                            Text(badge.uppercased()).font(Font2.sans(9, .heavy)).tracking(1)
                                .foregroundStyle(Theme.berry)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.berry.opacity(0.12), in: Capsule())
                        }
                    }
                    if let note {
                        Text(note).font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
                    }
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().strokeBorder(selected ? Theme.berry : Theme.ring, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if selected {
                        Circle().fill(Theme.berry).frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? Theme.berry : Theme.ring, lineWidth: selected ? 1.8 : 1))
            .animation(Motion.snappy, value: selected)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Length picker (duration rows + inline ruler for Custom)

/// Shared by onboarding's LengthStep and Settings' DurationView. Descriptive duration
/// rows replace any preset-pill row; Custom expands the ruler inline.
struct LengthPicker: View {
    @Binding var days: Int
    let startDate: Date
    @State private var customMode: Bool

    static let presets: [(days: Int, note: String)] = [
        (7,  "a one-week spark"),
        (14, "two weeks to warm up"),
        (30, "a month of momentum"),
        (75, "the full journey"),
    ]

    init(days: Binding<Int>, startDate: Date) {
        _days = days
        self.startDate = startDate
        _customMode = State(initialValue: !Self.presets.map(\.days).contains(days.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Self.presets, id: \.days) { p in
                OptionRow(title: "\(p.days) days", note: p.note,
                          badge: p.days == 75 ? "signature" : nil,
                          selected: !customMode && days == p.days) {
                    withAnimation(Motion.snappy) { customMode = false; days = p.days }
                }
            }
            OptionRow(title: "Custom", note: "you set the pace", selected: customMode) {
                withAnimation(Motion.snappy) { customMode = true }
            }
            if customMode {
                RulerSlider(value: $days, range: 1...75, unit: "days", accent: Theme.berry)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
            Text(range).font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 8)
        }
        .padding(.horizontal, 20)
        // The owner can set `days` after init (e.g. Settings loading the saved length):
        // if it lands off-preset, flip to Custom so the selection state matches the value.
        .onChange(of: days) { _, d in
            if !Self.presets.map(\.days).contains(d) && !customMode { customMode = true }
        }
    }

    private var range: String {
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: startDate) ?? startDate
        return "\(startDate.formatted(.dateTime.month(.abbreviated).day())) to \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

// MARK: - Day sticker card (the editorial "day N" receipt)

/// The shareable "day N" card. Onboarding's Ready step shows it as a numbered plan preview
/// ("day one"); the day-complete celebration shows it with the day's tasks checked off.
struct DayStickerCard: View {
    let dayWords: String            // spelled-out day: "one", "two"
    let range: String               // "jul 1 → sep 30"
    let tasks: [String]
    let challengeTitle: String
    var checked: Bool = false       // celebration = checkmarks; onboarding preview = numbers

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("day").font(Font2.serif(26, .medium)).italic().foregroundColor(Theme.ink)
             + Text(" \(dayWords)").font(Font2.serif(26, .semibold)).foregroundColor(Theme.ink))
            Text(range).font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(tasks.enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .top, spacing: 14) {
                        Group {
                            if checked {
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                            } else {
                                Text("\(i + 1)").font(Font2.serif(17, .medium)).foregroundStyle(Theme.ink.opacity(0.6))
                            }
                        }
                        .frame(width: 18, alignment: .leading)
                        Text(t).font(Font2.sans(13.5, .semibold)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }.padding(.top, 2)
            Divider().padding(.top, 4)
            HStack {
                Text(challengeTitle.uppercased()).font(Font2.sans(9, .bold)).tracking(1).foregroundStyle(Theme.ink.opacity(0.35))
                Spacer()
                Text("BY 75 HER").font(Font2.sans(9, .bold)).tracking(1).foregroundStyle(Theme.ink.opacity(0.35))
            }
        }
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foilSweepOnce(delay: 0.35)                 // laminated-sticker sheen (Metal)
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 10)
    }
}

/// A challenge date range formatted like the sticker ("jul 1 → sep 30").
func challengeRangeText(start: Date, days: Int) -> String {
    let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start) ?? start
    return "\(start.formatted(.dateTime.month(.abbreviated).day())) → \(end.formatted(.dateTime.month(.abbreviated).day()))".lowercased()
}

/// Day number spelled out ("two") for the sticker headline.
func dayInWords(_ n: Int) -> String {
    let f = NumberFormatter(); f.numberStyle = .spellOut
    return (f.string(from: NSNumber(value: n)) ?? "\(n)").lowercased()
}

// MARK: - Invite card (letterpress stationery showing your name + join code)

/// Reused by onboarding's "invite your friends" screen and the Friends tab. `code` is nil while
/// the code is still being provisioned (shows a placeholder). Styled like a letterpress
/// stationery card: cool porcelain stock with a double hairline border and a dashed rule.
struct InviteTicket: View {
    let name: String
    var code: String? = nil
    var compact: Bool = false            // show only the code half (no "Join <name>" header/rule)
    var shareText: String? = nil         // when set, a share icon appears inline next to the code
    var challenge: String = "75 Her"     // the selected challenge, shown as the card's eyebrow
    var ticketFill: Color = Color(hex: "F2EEF6")
    @State private var shareBounce = 0

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                VStack(spacing: 10) {
                    Text(challenge.uppercased()).font(Font2.sans(13, .bold)).tracking(5).foregroundStyle(Theme.ink.opacity(0.4))
                        .multilineTextAlignment(.center)
                    (Text("Join ").font(Font2.serif(30, .semibold)).foregroundColor(Theme.ink)
                     + Text(name.isEmpty ? "me" : name).font(Font2.serif(30, .semibold)).italic().foregroundColor(Theme.ink)
                     + Text("\nfor the challenge").font(Font2.serif(30, .semibold)).foregroundColor(Theme.ink))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 26).padding(.top, 46).padding(.bottom, 30)

                DashedRule().stroke(Theme.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [5, 7]))
                    .frame(height: 1.2).padding(.horizontal, 34)
            }

            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(code.map(SocialStore.format) ?? "•••• ••••")
                        .font(Font2.sans(34, .heavy)).tracking(4)
                        .foregroundStyle(code == nil ? Theme.ink.opacity(0.3) : Theme.ink)
                        .contentTransition(.numericText())
                        .animation(Motion.gentle, value: code)

                    if let shareText, code != nil {
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .symbolEffect(.bounce, value: shareBounce)
                                .foregroundStyle(Theme.ink.opacity(0.55))
                                .frame(width: 32, height: 32)
                                .background(Theme.ink.opacity(0.08), in: Circle())
                        }
                        .simultaneousGesture(TapGesture().onEnded { Haptics.tap(); shareBounce += 1 })
                        .accessibilityLabel("Share your invite code")
                    }
                }
                Text("Share this code with your circle")
                    .font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.4))
            }
            .padding(.horizontal, 26).padding(.top, compact ? 34 : 28).padding(.bottom, compact ? 34 : 46)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(ticketFill)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        }
        // Letterpress double hairline: one at the edge, one inset.
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.ink.opacity(0.14), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.ink.opacity(0.10), lineWidth: 1)
                .padding(7)
        }
    }
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
