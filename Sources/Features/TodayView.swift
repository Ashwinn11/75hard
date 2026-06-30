import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var page = 0
    @State private var editing = false
    private let tilts: [Double] = [-2.0, 1.6, -1.4, 2.0, -1.0, 1.2, -1.8, 1.0]

    private var challenge: Challenge? { challenges.first }

    var body: some View {
        VStack(spacing: 0) {
            if let c = challenge {
                TabHeader(day: c.currentDay) {
                    Button { editing = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44).background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                    }
                }
                PageDots(count: 2, index: page).padding(.top, 18)
                TabView(selection: $page) {
                    missionsPage(c).tag(0)
                    honeycombPage(c).tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                Spacer()
                ContentUnavailableView("No challenge yet", systemImage: "hexagon")
                Spacer()
            }
        }
        .her75Background()
        .sheet(isPresented: $editing) { if let c = challenge { EditHabitsSheet(challenge: c) } }
    }

    private func missionsPage(_ c: Challenge) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(Array(c.habitsOrdered.enumerated()), id: \.element.id) { i, h in
                    MissionCard(habit: h, done: h.isDoneToday, tilt: tilts[i % tilts.count]) {
                        HabitActions.toggleToday(h, context: context)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func honeycombPage(_ c: Challenge) -> some View {
        let photo = c.photoHabit
        let cells = c.transformationCells(photoHabit: photo)
        let captured = cells.filter { if case .empty = $0 { return false }; if case .camera = $0 { return false }; return true }.count
        return ScrollView {
            VStack(spacing: 14) {
                EyebrowLabel(text: "Your transformation", color: Theme.ink.opacity(0.45))
                HiveComb(color: photo?.color ?? .rose, cells: cells, width: 320, visibleCells: c.lengthDays,
                         onLog: { if let photo { HabitActions.toggleToday(photo, context: context) } })
                    .frame(maxWidth: .infinity)
                Text("\(captured) of \(c.lengthDays) days captured")
                    .font(Font2.sans(13, .bold)).foregroundStyle(Theme.ink.opacity(0.55))
            }
            .padding(.top, 24).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Shared minimal header (avatar + day badge + optional trailing button)

struct TabHeader<Trailing: View>: View {
    let day: Int
    @ViewBuilder var trailing: () -> Trailing
    @AppStorage("profilePhotoV") private var photoVersion = 0

    var body: some View {
        HStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                avatar
                Text("day \(day)")
                    .font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
                    .offset(y: 13)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 22).padding(.top, 10)
    }

    private var avatar: some View {
        ZStack {
            if let img = ProfilePhoto.load() {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.roseGradient
                Image(systemName: "person.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 66, height: 66).clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        .id(photoVersion)
    }
}

extension TabHeader where Trailing == EmptyView {
    init(day: Int) { self.init(day: day) { EmptyView() } }
}

// MARK: - Page dots (elongated active dot)

struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == index ? Theme.ink : Theme.ink.opacity(0.2))
                    .frame(width: i == index ? 20 : 7, height: 7)
            }
        }
    }
}

// MARK: - Edit tasks sheet (the pencil)

struct EditHabitsSheet: View {
    let challenge: Challenge
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(challenge.habitsOrdered) { h in
                    TextField("Task", text: Binding(get: { h.title }, set: { h.title = $0; try? context.save() }))
                        .font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
                }
            }
            .navigationTitle("Edit tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Profile bubble (used by the Profile screen)

struct ProfileBubble: View {
    let name: String
    @AppStorage("profilePhotoV") private var photoVersion = 0
    private var initials: String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return String(chars).uppercased()
    }
    var body: some View {
        ZStack {
            if let img = ProfilePhoto.load() {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.roseGradient
                if initials.isEmpty {
                    Image(systemName: "person.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                } else {
                    Text(initials).font(Font2.sans(18, .heavy)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: Theme.rose.opacity(0.3), radius: 8, x: 0, y: 4)
        .id(photoVersion)
    }
}
