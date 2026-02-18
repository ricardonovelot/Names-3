import SwiftUI

// MARK: - Quiz Design System
/// Centralized design tokens for the Face Quiz. Ensures consistency, supports Dynamic Type,
/// and provides a single source of truth for spacing, typography, and animation.
enum QuizDesign {
    
    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        
        static func content(compact: Bool) -> CGFloat { compact ? sm : lg }
        static func section(compact: Bool) -> CGFloat { compact ? sm : xl }
    }
    
    // MARK: - Typography (Dynamic Type friendly)
    enum Typography {
        static func title(compact: Bool) -> Font {
            .system(size: compact ? 15 : 17, weight: .semibold, design: .rounded)
        }
        static func body(compact: Bool) -> Font {
            .system(size: compact ? 13 : 15, weight: .regular, design: .default)
        }
        static func bodySemibold(compact: Bool) -> Font {
            .system(size: compact ? 13 : 15, weight: .semibold, design: .rounded)
        }
        static func caption(compact: Bool) -> Font {
            .system(size: compact ? 11 : 12, weight: .medium)
        }
        static func hint(compact: Bool) -> Font {
            .system(size: compact ? 16 : 20, weight: .medium, design: .monospaced)
        }
        static func feedback(compact: Bool) -> Font {
            .system(size: compact ? 14 : 17, weight: .bold, design: .rounded)
        }
    }
    
    // MARK: - Layout
    enum Layout {
        static func photoHeight(compact: Bool) -> CGFloat { compact ? 180 : 260 }
        static let horizontalPadding: CGFloat = 20
        static let cornerRadius: CGFloat = 12
        static let cornerRadiusCompact: CGFloat = 10
    }
    
    // MARK: - Animation
    enum Animation {
        static let questionTransition = SwiftUI.Animation.spring(response: 0.45, dampingFraction: 0.8)
        static let feedbackTransition = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let microInteraction = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.6)
    }
    
    // MARK: - Glass Stroke
    static var glassStroke: some ShapeStyle {
        LinearGradient(
            colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
