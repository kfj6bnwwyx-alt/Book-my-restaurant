import UIKit

/// Semantic haptics. Use the meaning, not the raw generator, so feedback stays
/// consistent: success on a confirmed table, selection on a slot tap, warning on
/// a partial result, error on a failed booking.
enum RBHaptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
