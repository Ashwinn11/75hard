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
    }
}

// MARK: - Selector pill — ink-filled when selected, white with a ring otherwise

struct SelectPill: View {
    let text: String
    let selected: Bool
    var hPad: CGFloat = 18
    var vPad: CGFloat = 11
    var action: () -> Void
    var body: some View {
        Button { Haptics.select(); action() } label: {
            Text(text).font(Font2.sans(15, .bold)).foregroundStyle(selected ? .white : Theme.ink)
                .padding(.horizontal, hPad).padding(.vertical, vPad)
                .background(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color.white), in: Capsule())
                .overlay(Capsule().stroke(Theme.ring, lineWidth: selected ? 0 : 1.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile avatar (the user's photo, or the rose placeholder) in a white-ringed circle

struct ProfileAvatar: View {
    var size: CGFloat = 66
    @AppStorage("profilePhotoV") private var photoVersion = 0

    var body: some View {
        ZStack {
            if let img = ProfilePhoto.load() {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.roseGradient
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: max(2, size / 44)))
        .shadow(color: .black.opacity(0.10), radius: size / 9, y: size / 18)
        .id(photoVersion)
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

// MARK: - Challenge photo-strip card (4 photos + floating pill + title)

/// The one challenge card used everywhere — onboarding's library, the profile card, and the
/// switch-challenge flow — so a track always shows the same photos and fallback colors.
struct ChallengeStripCard: View {
    let track: ChallengeTrack
    var pillText: String? = nil      // override for the floating pill; nil → the track's joined count
    var height: CGFloat = 108
    var showTitle = true

    private var pill: String? { pillText ?? (track.joined.isEmpty ? nil : track.joined) }

    // Deterministic palette seed (String.hashValue is randomized per launch).
    private var seed: Int {
        var h = 5381
        for b in track.rawValue.utf8 { h = (h &* 33) &+ Int(b) }
        return abs(h)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .top) {
                HStack(spacing: 3) {
                    ForEach(Array(track.photos.enumerated()), id: \.offset) { i, p in
                        PhotoFill(name: p, fallback: HabitColor.palette[(seed + i) % HabitColor.palette.count].gradient)
                            .frame(maxWidth: .infinity).frame(height: height).clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if let pill {
                    HStack(spacing: 5) {
                        if pillText != nil {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                        }
                        Text(pill).font(Font2.sans(11, .bold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2).offset(y: -11)
                }
            }
            if showTitle && pillText == nil {   // pill already names the challenge — don't repeat it below
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
            ChallengeStripCard(track: track, height: 96, showTitle: false)
            Button { onAdd() } label: {
                Text("Create Daily Task +").font(Font2.sans(15, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    row(i, item)
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
                TextField("Add a note", text: $draft.subtitle)
                    .font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.7))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(draft.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 12) {
                ForEach(HabitColor.palette) { c in
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

// MARK: - Length picker (ruler + preset pills + date-range caption)

/// Shared by onboarding's LengthStep and Settings' DurationView.
struct LengthPicker: View {
    @Binding var days: Int
    let startDate: Date
    var showsCustomBadge = false        // onboarding shows a "Custom" state pill under the presets

    static let presets = [7, 14, 30, 75]

    var body: some View {
        VStack(spacing: 0) {
            RulerSlider(value: $days, range: 1...75, unit: "days", accent: Theme.sage)
                .padding(.horizontal, 16)
            HStack(spacing: 10) {
                ForEach(Self.presets, id: \.self) { p in
                    SelectPill(text: "\(p)", selected: days == p) { withAnimation { days = p } }
                }
            }.padding(.top, 20)
            if showsCustomBadge {
                Text("Custom")
                    .font(Font2.sans(15, .bold)).foregroundStyle(Self.presets.contains(days) ? Theme.ink : .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Self.presets.contains(days) ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.ink), in: Capsule())
                    .overlay(Capsule().stroke(Theme.ring, lineWidth: Self.presets.contains(days) ? 1.5 : 0))
                    .padding(.horizontal, 30).padding(.top, 10)
            }
            Text(range).font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 16)
        }
    }

    private var range: String {
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: startDate) ?? startDate
        return "\(startDate.formatted(.dateTime.month(.abbreviated).day())) to \(end.formatted(.dateTime.month(.abbreviated).day()))"
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
