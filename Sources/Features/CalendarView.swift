import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var anchor = Date()
    @State private var selectedDate = Date()
    private let cal = Calendar.current

    private var challenge: Challenge? { challenges.first }

    var body: some View {
        VStack(spacing: 0) {
            if let c = challenge {
                TabHeader(day: c.currentDay)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        monthHeader
                        weekdayRow
                        grid(for: c)
                        legend
                        daySection(c)
                    }
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
                ContentUnavailableView("No challenge yet", systemImage: "calendar")
                Spacer()
            }
        }
        .her75Background()
    }

    private var monthHeader: some View {
        HStack {
            Text(anchor.formatted(.dateTime.month(.wide).year()))
                .font(Font2.sans(18, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
            ForEach([-1, 1], id: \.self) { dir in
                Button {
                    Haptics.select()
                    if let d = cal.date(byAdding: .month, value: dir, to: anchor) { anchor = d }
                } label: {
                    Image(systemName: dir < 0 ? "chevron.left" : "chevron.right")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34).background(.white, in: Circle())
                        .overlay(Circle().stroke(Theme.ring, lineWidth: 1))
                }
            }
        }
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                Text(d).font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func grid(for c: Challenge) -> some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, c)
                } else {
                    Color.clear.frame(height: 42)
                }
            }
        }
    }

    private func dayCell(_ date: Date, _ c: Challenge) -> some View {
        let frac = fraction(date, c)
        let isToday = cal.isDateInToday(date)
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        return Button {
            Haptics.select(); selectedDate = date
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill(frac))
                if isToday {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.ink, lineWidth: 2)
                } else if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.coral, lineWidth: 2)
                }
                Text("\(cal.component(.day, from: date))")
                    .font(Font2.sans(13, .bold))
                    .foregroundStyle(frac != nil && frac! > 0.5 ? .white : Theme.ink.opacity(frac == nil ? 0.25 : 0.8))
            }
            .frame(height: 42)
        }
        .buttonStyle(.plain)
    }

    /// The selected day's missions, shown as cards (strikethrough reflects that day's completion).
    private func daySection(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(Font2.serif(22, .semibold)).foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(c.habitsOrdered) { h in
                    MissionCard(habit: h, done: h.completion(on: selectedDate) != nil) {}
                }
            }
        }
        .padding(.top, 10)
    }

    private func fill(_ frac: Double?) -> Color {
        guard let frac else { return Color.white.opacity(0.5) }
        if frac >= 1 { return Theme.rose }
        if frac > 0  { return Theme.coral.opacity(0.45 + frac * 0.4) }
        return Theme.chipFill
    }

    /// Completion fraction for a date, or nil if it's outside the challenge window.
    private func fraction(_ date: Date, _ c: Challenge) -> Double? {
        let start = cal.startOfDay(for: c.startDate)
        guard let end = cal.date(byAdding: .day, value: c.lengthDays, to: start),
              date >= start, date < end, date <= Date() else { return nil }
        let habits = c.habitsOrdered
        guard !habits.isEmpty else { return 0 }
        let done = habits.filter { $0.completion(on: date) != nil }.count
        return Double(done) / Double(habits.count)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendDot(Theme.rose, "Complete")
            legendDot(Theme.coral.opacity(0.6), "Partial")
            legendDot(Theme.chipFill, "Missed")
        }.padding(.top, 4)
    }
    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(c).frame(width: 14, height: 14)
            Text(t).font(Font2.sans(12, .medium)).foregroundStyle(Theme.ink.opacity(0.6))
        }
    }

    /// Days of the displayed month padded with leading nils to the first weekday.
    private func monthDays() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: anchor) else { return [] }
        let first = interval.start
        let leading = cal.component(.weekday, from: first) - 1   // Sunday = 1
        let count = cal.range(of: .day, in: .month, for: anchor)?.count ?? 30
        var out: [Date?] = Array(repeating: nil, count: leading)
        for i in 0..<count {
            out.append(cal.date(byAdding: .day, value: i, to: first))
        }
        return out
    }
}
