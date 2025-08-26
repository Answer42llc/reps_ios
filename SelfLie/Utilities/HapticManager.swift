import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptic Feedback Types (platform-neutral API)
enum ImpactStyle {
    case light
    case medium
    case heavy
    case rigid
    case soft
}

enum NotificationType {
    case success
    case warning
    case error
}

enum HapticFeedback {
    case impact(ImpactStyle)
    case selection
    case notification(NotificationType)
    
    // Convenience cases for common patterns
    static let lightImpact = HapticFeedback.impact(.light)
    static let mediumImpact = HapticFeedback.impact(.medium)
    static let heavyImpact = HapticFeedback.impact(.heavy)
    static let success = HapticFeedback.notification(.success)
    static let warning = HapticFeedback.notification(.warning)
    static let error = HapticFeedback.notification(.error)
}

// MARK: - SwiftUI View Modifier for Haptic Feedback
struct HapticFeedbackModifier: ViewModifier {
    let feedback: HapticFeedback
    let trigger: Bool
    
    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, newValue in
                if newValue {
                    HapticManager.shared.trigger(feedback)
                }
            }
    }
}

// MARK: - SwiftUI View Extension
extension View {
    /// Adds haptic feedback to a view when a trigger value changes to true
    func hapticFeedback(_ feedback: HapticFeedback, trigger: Bool) -> some View {
        modifier(HapticFeedbackModifier(feedback: feedback, trigger: trigger))
    }
    
    /// Adds haptic feedback to a button or tappable view
    func hapticFeedbackOnTap(_ feedback: HapticFeedback = .mediumImpact) -> some View {
        self.onTapGesture {
            HapticManager.shared.trigger(feedback)
        }
    }
    
    /// Adds haptic feedback with simultaneous tap gesture (doesn't block other gestures)
    func withHapticFeedback(_ feedback: HapticFeedback = .mediumImpact) -> some View {
        self.simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    HapticManager.shared.trigger(feedback)
                }
        )
    }
}

// MARK: - Haptic Manager (Internal Implementation)
@MainActor
class HapticManager {
    
    // MARK: - Singleton
    static let shared = HapticManager()
    
    #if canImport(UIKit)
    // MARK: - Feedback Generators (cached for performance)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    // 最近一次为各风格准备的时间，用于智能预准备节流
    private var lastImpactPrepareAt: [ImpactStyle: Date] = [:]
    #endif
    
    private init() {
        // Prepare generators on initialization for better performance
        prepareGenerators()
    }
    
    // MARK: - Preparation Methods
    private func prepareGenerators() {
        #if canImport(UIKit)
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        selectionFeedback.prepare()
        notificationFeedback.prepare()
        #endif
    }
    
    // MARK: - Main Trigger Method
    func trigger(_ feedback: HapticFeedback) {
        #if canImport(UIKit)
        switch feedback {
        case .impact(let style):
            triggerImpact(style)
        case .selection:
            triggerSelection()
        case .notification(let type):
            triggerNotification(type)
        }
        #endif
    }
    
    #if canImport(UIKit)
    private func conditionallyPrepareImpact(_ style: ImpactStyle, window seconds: TimeInterval = 1.5) {
        let now = Date()
        if let last = lastImpactPrepareAt[style], now.timeIntervalSince(last) < seconds {
            return
        }
        switch style {
        case .light: lightImpact.prepare()
        case .medium: mediumImpact.prepare()
        case .heavy: heavyImpact.prepare()
        case .rigid: rigidImpact.prepare()
        case .soft: softImpact.prepare()
        }
        lastImpactPrepareAt[style] = now
    }
    
    private func triggerImpact(_ style: ImpactStyle) {
        switch style {
        case .light:
            conditionallyPrepareImpact(.light)
            lightImpact.impactOccurred()
        case .medium:
            conditionallyPrepareImpact(.medium)
            mediumImpact.impactOccurred()
        case .heavy:
            conditionallyPrepareImpact(.heavy)
            heavyImpact.impactOccurred()
        case .rigid:
            conditionallyPrepareImpact(.rigid)
            rigidImpact.impactOccurred()
        case .soft:
            conditionallyPrepareImpact(.soft)
            softImpact.impactOccurred()
        }
    }
    
    private func triggerSelection() {
        selectionFeedback.prepare()  // Prepare before triggering
        selectionFeedback.selectionChanged()
    }
    
    private func triggerNotification(_ type: NotificationType) {
        notificationFeedback.prepare()  // Prepare before triggering
        switch type {
        case .success: notificationFeedback.notificationOccurred(.success)
        case .warning: notificationFeedback.notificationOccurred(.warning)
        case .error: notificationFeedback.notificationOccurred(.error)
        }
    }
    #endif
}

extension HapticManager {
    /// 提前准备 Impact 引擎，建议在即将触发的 1-2 秒内调用
    func prepareImpact(_ style: ImpactStyle) {
        #if canImport(UIKit)
        switch style {
        case .light:
            lightImpact.prepare()
        case .medium:
            mediumImpact.prepare()
        case .heavy:
            heavyImpact.prepare()
        case .rigid:
            rigidImpact.prepare()
        case .soft:
            softImpact.prepare()
        }
        #endif
    }
}

// MARK: - SwiftUI Button Style with Haptic Feedback
struct HapticButtonStyle: ButtonStyle {
    let feedback: HapticFeedback
    
    init(feedback: HapticFeedback = .mediumImpact) {
        self.feedback = feedback
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    HapticManager.shared.trigger(feedback)
                }
            }
    }
}
