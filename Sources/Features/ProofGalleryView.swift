import SwiftUI
import UIKit

// MARK: - Proof photo model

/// One proof photo, resolved from a Completion that carries a `photoFilename`.
struct ProofShot: Identifiable, Equatable {
    let id: UUID            // the Completion's id
    let dayIndex: Int
    let date: Date
    let habitTitle: String
    let filename: String

    var url: URL { AppGroup.photosURL.appendingPathComponent(filename) }

    /// Every proof photo in a challenge, newest first.
    static func all(in challenge: Challenge) -> [ProofShot] {
        challenge.habits
            .flatMap { h in
                h.completions.compactMap { c -> ProofShot? in
                    guard let f = c.photoFilename else { return nil }
                    return ProofShot(id: c.id, dayIndex: c.dayIndex, date: c.loggedAt,
                                     habitTitle: h.title, filename: f)
                }
            }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Decode cache (avoids re-decoding on every scroll / re-open)

enum ProofImageCache {
    static let store: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()

    /// Downsampled decode off the main actor, memoized by filename + size.
    static func image(for shot: ProofShot, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(shot.filename)@\(Int(maxPixel))" as NSString
        if let hit = store.object(forKey: key) { return hit }
        let url = shot.url
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ImageProcessing.thumbnail(data, maxPixel: maxPixel)
        }.value
        if let decoded { store.setObject(decoded, forKey: key) }
        return decoded
    }
}

/// An async-loaded proof image that fades in and honors the decode cache.
struct ProofImage: View {
    let shot: ProofShot
    var maxPixel: CGFloat
    var fill: Bool = true
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
                    .transition(.opacity)
            } else {
                Theme.chipFill
            }
        }
        .task(id: shot.id) {
            let img = await ProofImageCache.image(for: shot, maxPixel: maxPixel)
            withAnimation(Motion.gentle) { image = img }
        }
    }
}

// MARK: - Proof calendar (rendered inline on the Profile page)

/// A photo calendar of the challenge — one month grid per month it spans. Days with a proof
/// photo show the photo; tapping a day hands its photos back for the viewer.
struct ProofCalendar: View {
    let challenge: Challenge
    var onTapDay: ([ProofShot]) -> Void

    private let cal = Calendar.current

    var body: some View {
        let shots = ProofShot.all(in: challenge)
        let byDay = Dictionary(grouping: shots) { cal.startOfDay(for: $0.date) }
        VStack(spacing: 26) {
            ForEach(months, id: \.self) { m in
                MonthGrid(month: m, byDay: byDay, range: range, today: cal.startOfDay(for: Date()), onTapDay: onTapDay)
            }
        }
    }

    private var range: ClosedRange<Date> {
        let start = cal.startOfDay(for: challenge.startDate)
        let last = cal.date(byAdding: .day, value: challenge.lengthDays - 1, to: start) ?? start
        return start...last
    }

    /// Month-starts spanning the challenge (start → min(end, today)).
    private var months: [Date] {
        let start = cal.startOfDay(for: challenge.startDate)
        let last = cal.date(byAdding: .day, value: challenge.lengthDays - 1, to: start) ?? start
        let end = max(start, min(last, cal.startOfDay(for: Date())))
        guard var m = cal.date(from: cal.dateComponents([.year, .month], from: start)) else { return [] }
        let endMonth = cal.date(from: cal.dateComponents([.year, .month], from: end)) ?? m
        var out: [Date] = []
        while m <= endMonth {
            out.append(m)
            guard let next = cal.date(byAdding: .month, value: 1, to: m) else { break }
            m = next
        }
        return out
    }
}

private struct MonthGrid: View {
    let month: Date                          // first-of-month
    let byDay: [Date: [ProofShot]]
    let range: ClosedRange<Date>             // the challenge span (start...end)
    let today: Date
    var onTapDay: ([ProofShot]) -> Void

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(Font2.serif(20, .semibold)).foregroundStyle(Theme.ink)

            HStack(spacing: 6) {
                // Weekday symbols repeat ("S","T"), so key by position, not value.
                ForEach(Array(orderedWeekdays.enumerated()), id: \.offset) { _, s in
                    Text(s).font(Font2.sans(11, .bold)).foregroundStyle(Theme.ink.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let shots = byDay[date] ?? []
        let inRange = date >= cal.startOfDay(for: range.lowerBound) && date <= cal.startOfDay(for: range.upperBound)
        let isToday = cal.isDate(date, inSameDayAs: today)
        let dayNum = cal.component(.day, from: date)
        let hasPhoto = shots.first != nil

        return Button { onTapDay(shots) } label: {
            // A square container (ProofImage has no intrinsic ratio). The fill image
            // overflows its own frame, so the CLIP has to live on this outer square —
            // otherwise a 3:4 photo spills past the tile.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let first = shots.first {
                        ProofImage(shot: first, maxPixel: 220)
                    } else {
                        (inRange ? Theme.chipFill : Color.clear)
                            .overlay {
                                Text("\(dayNum)")
                                    .font(Font2.sans(13, .semibold))
                                    .foregroundStyle(Theme.ink.opacity(inRange ? 0.45 : 0.18))
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if hasPhoto {
                        Text("\(dayNum)")
                            .font(Font2.sans(9, .bold)).foregroundStyle(.white)
                            .padding(3).background(.black.opacity(0.3), in: Capsule()).padding(3)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if shots.count > 1 {
                        Text("\(shots.count)")
                            .font(Font2.sans(9, .heavy)).foregroundStyle(.white)
                            .padding(4).background(.black.opacity(0.4), in: Circle()).padding(3)
                    }
                }
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.mauve, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .disabled(!hasPhoto)
    }

    // Leading blanks for the first weekday, then each day of the month.
    private var cells: [Date?] {
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps),
              let daysRange = cal.range(of: .day, in: .month, for: first) else { return [] }
        let weekdayOf1st = cal.component(.weekday, from: first)          // 1...7
        let leading = (weekdayOf1st - cal.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: leading)
        for d in daysRange {
            out.append(cal.date(byAdding: .day, value: d - 1, to: first))
        }
        return out
    }

    private var orderedWeekdays: [String] {
        let symbols = cal.veryShortWeekdaySymbols                        // index 0 = Sunday
        return (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }
    }
}

// MARK: - Day viewer (full-screen photos for a tapped date)

/// The photos of one day, presented full screen: a swipeable pager with pull-to-dismiss + share.
struct ProofDay: Identifiable {
    let id = UUID()
    let shots: [ProofShot]
}

struct ProofViewer: View {
    let shots: [ProofShot]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var dismissDrag: CGFloat = 0
    @State private var pageDrag: CGFloat = 0
    @State private var dragAxis: Axis? = nil
    @State private var didShare = false     // shared a proof → ask for a rating on the way out

    var body: some View {
        ZStack {
            Color.black.opacity(1 - min(Double(dismissDrag), 260) / 340).ignoresSafeArea()

            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    ForEach(Array(shots.enumerated()), id: \.element.id) { j, s in
                        Group {
                            if abs(j - index) <= 1 {
                                ProofImage(shot: s, maxPixel: 1500, fill: false)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: w, height: geo.size.height)
                    }
                }
                .offset(x: -CGFloat(index) * w + pageDrag, y: dismissDrag)
                .scaleEffect(1 - min(dismissDrag, 300) / 1500)
                .contentShape(Rectangle())
                .gesture(drag(width: w))
            }
            .ignoresSafeArea()

            chrome.opacity(1 - min(dismissDrag, 160) / 160)
        }
        .statusBarHidden()
        // Fire on the way out so the review sheet doesn't collide with the share sheet.
        .onDisappear { if didShare { Ratings.note(.sharedProgress) } }
    }

    private func drag(width w: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { g in
                if dragAxis == nil {
                    if abs(g.translation.width) > abs(g.translation.height) + 4 { dragAxis = .horizontal }
                    else if abs(g.translation.height) > 8 { dragAxis = .vertical }
                }
                switch dragAxis {
                case .horizontal:
                    var dx = g.translation.width
                    if (index == 0 && dx > 0) || (index == shots.count - 1 && dx < 0) { dx *= 0.32 }
                    pageDrag = dx
                case .vertical:
                    dismissDrag = max(0, g.translation.height)
                default: break
                }
            }
            .onEnded { g in
                defer { dragAxis = nil }
                switch dragAxis {
                case .horizontal:
                    let predicted = g.predictedEndTranslation.width
                    var next = index
                    if predicted < -w * 0.22, index < shots.count - 1 { next += 1 }
                    if predicted >  w * 0.22, index > 0 { next -= 1 }
                    if next != index { Haptics.select() }
                    withAnimation(Motion.snappy) { index = next; pageDrag = 0 }
                case .vertical:
                    if dismissDrag > 120 { Haptics.tap(); dismiss() }
                    else { withAnimation(Motion.bouncy) { dismissDrag = 0 } }
                default: break
                }
            }
    }

    @ViewBuilder private var chrome: some View {
        if shots.indices.contains(index) {
            let shot = shots[index]
            VStack {
                HStack {
                    Spacer()
                    ShareLink(item: shot.url) { icon("square.and.arrow.up") }
                        .simultaneousGesture(TapGesture().onEnded { Haptics.tap(); didShare = true })
                    Button { Haptics.tap(); dismiss() } label: { icon("xmark") }
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
                VStack(spacing: 3) {
                    Text("Day \(shot.dayIndex)").font(Font2.serif(30, .semibold)).foregroundStyle(.white)
                    Text(shot.habitTitle).font(Font2.sans(14, .bold)).foregroundStyle(.white.opacity(0.85))
                    Text(shot.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Font2.sans(12, .medium)).foregroundStyle(.white.opacity(0.6))
                }
                .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                .padding(.bottom, 30)
            }
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            .frame(width: 40, height: 40).background(.black.opacity(0.32), in: Circle())
    }
}
