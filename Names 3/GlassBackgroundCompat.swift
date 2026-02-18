import SwiftUI

enum LiquidGlassStyle {
    case regular
    case clear
    /// More transparent, like Apple Music tab bar—content visible beneath.
    case translucent
}

extension View {
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S) -> some View {
        liquidGlass(in: shape, stroke: true)
    }

    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, stroke: Bool) -> some View {
        liquidGlass(in: shape, stroke: stroke, style: .regular)
    }

    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, stroke: Bool = true, style: LiquidGlassStyle) -> some View {
        if #available(iOS 26.0, *) {
            switch style {
            case .regular:
                self.glassEffect(.regular, in: shape)
            case .clear:
                self.glassEffect(.clear, in: shape)
            case .translucent:
                self.glassEffect(.clear, in: shape)
            }
        } else {
            let material: Material = style == .translucent ? .ultraThinMaterial : .thinMaterial
            self
                .background(material, in: shape)
                .overlay {
                    if stroke {
                        shape.stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(style == .translucent ? 0.12 : 0.18),
                                    Color.white.opacity(style == .translucent ? 0.03 : 0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                    }
                }
        }
    }
}

@available(iOS 26.0, *)
private extension View {
    func _liquidGlass18<S: InsettableShape>(in shape: S) -> some View {
        self.glassEffect(.regular, in: shape)
    }
}

// MARK: - Liquid glass close button (matches ContactDetailsView circle buttons)

/// Close (X) button with liquid glass circle background. Use from SwiftUI or via UIHostingController in UIKit.
struct LiquidGlassCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
                .liquidGlass(in: Circle(), stroke: true, style: .clear)
        }
        .buttonStyle(.plain)
    }
}

/// Magnifying glass button with liquid glass circle background (e.g. for "Next" / find next in Name Faces).
struct LiquidGlassMagnifyingGlassButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
                .liquidGlass(in: Circle(), stroke: true, style: .clear)
        }
        .buttonStyle(.plain)
    }
}

/// Next (magnifying) button that shows a loading spinner in place of the icon while loading.
struct LiquidGlassNextButtonView: View {
    var isLoading: Bool
    var action: () -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.9)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .liquidGlass(in: Circle(), stroke: true, style: .clear)
            } else {
                Button(action: action) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.secondary)
                        .contentShape(Circle())
                        .liquidGlass(in: Circle(), stroke: true, style: .clear)
                }
                .buttonStyle(.plain)
            }
        }
    }
}