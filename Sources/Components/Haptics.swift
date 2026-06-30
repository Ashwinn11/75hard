import UIKit

/// Thin wrapper over UIKit feedback generators. The brand leans on "good haptic feel" —
/// soft taps on completion, success on a finished day, selection on pickers.
enum Haptics {
    static func tap()     { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func rigid()   { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func select()  { UISelectionFeedbackGenerator().selectionChanged() }
}
