import SwiftUI
import SwiftData

struct WallpaperView: View {
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var gradientIndex = 0
    @State private var position: TextPos = .bottom
    @State private var showTasks = false
    @State private var shareImage: Image?

    private var challenge: Challenge? { challenges.first }

    static let gradients: [[Color]] = [
        [Color(hex: "C24E57"), Color(hex: "9B3A52")],
        [Color(hex: "3B1A2A"), Color(hex: "2A1620")],
        [Color(hex: "F2A5AE"), Color(hex: "C24E57")],
        [Color(hex: "E7CBB0"), Color(hex: "C98B6B")],
        [Color(hex: "CBA6E6"), Color(hex: "7C5FB0")],
        [Color(hex: "A9C2E8"), Color(hex: "5F7CB0")],
        [Color(hex: "A8C49C"), Color(hex: "5F8A6E")],
        [Color(hex: "FBEDE9"), Color(hex: "E89BA0")],
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "Make it yours")
                    (Text("Your ").font(Font2.serif(34, .semibold)).foregroundColor(Theme.ink)
                     + Text("wallpaper").font(Font2.serif(34, .semibold)).italic().foregroundColor(Theme.rose))
                }

                canvas
                    .aspectRatio(390.0 / 760.0, contentMode: .fit)
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 18, y: 10)
                    .frame(maxWidth: .infinity)

                controls

                Button {
                    render()
                } label: {
                    Text("Create wallpaper")
                        .font(Font2.sans(17, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.roseGradient, in: Capsule())
                }
                if let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview("75 Her wallpaper", image: shareImage)) {
                        Text("Save / share")
                            .font(Font2.sans(16, .bold)).foregroundStyle(Theme.rose)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(.white, in: Capsule())
                            .overlay(Capsule().stroke(Theme.rose.opacity(0.4), lineWidth: 1.5))
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .her75Background()
    }

    private var canvas: some View {
        WallpaperCanvas(colors: Self.gradients[gradientIndex], position: position,
                        name: challenge?.ownerName ?? "", day: challenge?.currentDay ?? 1,
                        track: challenge?.track.title ?? "75 Her",
                        tasks: showTasks ? (challenge?.habitsOrdered.map(\.title) ?? []) : [])
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.gradients.indices, id: \.self) { i in
                        Circle()
                            .fill(LinearGradient(colors: Self.gradients[i], startPoint: .top, endPoint: .bottom))
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Theme.ink, lineWidth: gradientIndex == i ? 2.5 : 0))
                            .onTapGesture { Haptics.select(); gradientIndex = i }
                    }
                }
            }
            Picker("Text", selection: $position) {
                Text("Top").tag(TextPos.top); Text("Center").tag(TextPos.center); Text("Bottom").tag(TextPos.bottom)
            }.pickerStyle(.segmented)
            Toggle(isOn: $showTasks) {
                Text("Overlay today's tasks").font(Font2.sans(15, .bold)).foregroundStyle(Theme.ink)
            }.tint(Theme.rose)
        }
    }

    @MainActor private func render() {
        let renderer = ImageRenderer(content: canvas.frame(width: 390, height: 844))
        renderer.scale = 3
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
            Haptics.success()
        }
    }
}

enum TextPos { case top, center, bottom }

/// The full wallpaper design — rendered to an image for export.
struct WallpaperCanvas: View {
    let colors: [Color]
    let position: TextPos
    let name: String
    let day: Int
    let track: String
    var tasks: [String] = []

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 10) {
                if position != .top { Spacer() }
                Text(track.uppercased())
                    .font(Font2.sans(13, .bold)).tracking(3).foregroundStyle(.white.opacity(0.85))
                (Text("Day ").font(Font2.serif(64, .semibold)).foregroundColor(.white)
                 + Text("\(day)").font(Font2.serif(64, .bold)).italic().foregroundColor(.white))
                if !name.isEmpty {
                    Text("Become Her, \(name)").font(Font2.serif(26, .medium)).italic().foregroundStyle(.white.opacity(0.92))
                }
                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tasks.prefix(6), id: \.self) { t in
                            HStack(spacing: 8) {
                                Image(systemName: "circle").font(.system(size: 12, weight: .bold))
                                Text(t).font(Font2.sans(14, .semibold))
                            }.foregroundStyle(.white.opacity(0.9))
                        }
                    }.padding(.top, 10)
                }
                if position != .bottom { Spacer() }
            }
            .padding(34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position == .center ? .leading : .leading)
        }
    }
}
