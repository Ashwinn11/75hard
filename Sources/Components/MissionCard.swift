import SwiftUI

/// A daily mission: a photo card with the task name in a frosted chip. Tapping toggles
/// completion, which simply **strikes through** the name (no checkbox).
struct MissionCard: View {
    let habit: Habit
    let done: Bool
    var tilt: Double = 0
    var onTap: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            ZStack(alignment: .bottomLeading) {
                PhotoFill(name: habit.photoName, fallback: habit.color.gradient)
                LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .center, endPoint: .bottom)
                if done {
                    Rectangle().fill(.white.opacity(0.35))           // subtle done wash
                }
                Text(habit.title)
                    .font(Font2.sans(14.5, .bold))
                    .foregroundStyle(Theme.ink)
                    .strikethrough(done, color: Theme.ink.opacity(0.7))
                    .opacity(done ? 0.6 : 1)
                    .lineLimit(1)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 162)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            .rotationEffect(.degrees(tilt))
        }
        .buttonStyle(PressableStyle())
    }
}
