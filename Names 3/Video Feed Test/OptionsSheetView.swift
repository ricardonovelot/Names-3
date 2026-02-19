import SwiftUI
import Combine
import MediaPlayer

private enum OptionsTheme {
    static let text = Color.primary
    static let secondaryText = Color.secondary
    static let background = Color(red: 0.07, green: 0.08, blue: 0.09).opacity(0.36)
    static let separator = Color.white.opacity(0.12)
    static let subtleFill = Color.white.opacity(0.06)
    static let chipFill = Color.white.opacity(0.08)
    static let placeholderFill = Color.white.opacity(0.06)
    static let grabber = Color.white.opacity(0.4)
}

@MainActor
final class OptionsCoordinator: ObservableObject {
    @Published private(set) var base: CGFloat = 0
    @Published private(set) var gestureDelta: CGFloat = 0
    @Published var isPresented: Bool = false
    @Published private(set) var isInteracting: Bool = false

    var progress: CGFloat { clamp01(base + gestureDelta) }

    func beginOpenInteraction() {
        withAnimation(nil) {
            base = progress
            gestureDelta = 0
            isInteracting = true
        }
    }

    func updateOpenDrag(dy: CGFloat, distance: CGFloat) {
        let target = clamp01(-dy / max(distance, 1))
        withAnimation(nil) {
            gestureDelta = target - base
        }
    }

    func endOpen(velocityUp: CGFloat) {
        let p = progress
        let shouldOpen = p > 0.25 || velocityUp > 900
        let stiffness: CGFloat = velocityUp > 1400 ? 280 : 220
        let damping: CGFloat = 28
        isInteracting = false
        withAnimation(.interpolatingSpring(stiffness: stiffness, damping: damping)) {
            base = shouldOpen ? 1 : 0
            gestureDelta = 0
            isPresented = shouldOpen
        }
    }

    func beginCloseInteraction() {
        withAnimation(nil) {
            base = progress
            gestureDelta = 0
            isInteracting = true
        }
    }

    func updateCloseDrag(dy: CGFloat, distance: CGFloat) {
        let target = clamp01(base - (dy / max(distance, 1)))
        withAnimation(nil) {
            gestureDelta = target - base
        }
    }

    func endClose(velocityDown: CGFloat) {
        let p = progress
        let shouldClose = p < 0.6 || velocityDown > 900
        let stiffness: CGFloat = velocityDown > 1400 ? 280 : 220
        let damping: CGFloat = 28
        isInteracting = false
        withAnimation(.interpolatingSpring(stiffness: stiffness, damping: damping)) {
            base = shouldClose ? 0 : 1
            gestureDelta = 0
            isPresented = !shouldClose
        }
    }
}

struct OptionsPinnedTransform: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let targetH = targetPinnedHeight(for: size)
            let minScale = min(1.0, max(0.01, targetH / max(1, size.height)))
            let s = lerp(1.0, minScale, clamp01(progress))
            content
                .scaleEffect(s, anchor: .top)
                .shadow(color: Color.black.opacity(0.25 * clamp01(progress)), radius: 10 * clamp01(progress), x: 0, y: 6 * clamp01(progress))
                .ignoresSafeArea()
                .animation(nil, value: size)
        }
    }
}

extension View {
    func optionsPinnedTopTransform(progress: CGFloat) -> some View {
        modifier(OptionsPinnedTransform(progress: progress))
    }
}

struct OptionsSheet: View {
    @ObservedObject var options: OptionsCoordinator
    let currentAssetID: String?
    let onDelete: () -> Void
    let onShare: () -> Void
    let onOpenSettings: () -> Void
    @State private var isClosingDrag = false
    @State private var panelHeight: CGFloat = 0
    @ObservedObject private var videoVolume = VideoVolumeManager.shared
    @State private var perVideoVolume: Float?
    @ObservedObject private var music = MusicCenter.shared

    var body: some View {
        GeometryReader { proxy in
            let progress = options.progress
            let reveal = clamp01(progress)
            let bottomInset = proxy.safeAreaInsets.bottom
            let measured = panelHeight > 0 ? panelHeight : proxy.size.height * 0.4
            let offscreen = measured + bottomInset + 24
            let containerH = proxy.size.height
            let pinnedH = targetPinnedHeight(for: proxy.size)
            let yMin = max(0, pinnedH + measured - containerH)
            let travel = max(1, offscreen - yMin)
            let yOffset = yMin + (1 - reveal) * travel

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.0001 + 0.24 * reveal)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Options")
                                .font(.headline)
                                .foregroundColor(OptionsTheme.text)
                            Spacer()
                            if currentAssetID != nil {
                                Button {
                                    onDelete()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.red)
                                        .padding(10)
                                        .background(
                                            Circle().fill(OptionsTheme.chipFill)
                                                .overlay(Circle().stroke(OptionsTheme.separator, lineWidth: 1))
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete video")
                                .accessibilityHint("Deletes the current video from your feed")
                            }
                            GlassCloseButton {
                                options.beginCloseInteraction()
                                options.updateCloseDrag(dy: 999, distance: 999)
                                options.endClose(velocityDown: 1000)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Video volume")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(OptionsTheme.text)
                            HStack(spacing: 12) {
                                Slider(value: Binding(
                                    get: {
                                        if let _ = currentAssetID, let local = perVideoVolume {
                                            return Double(local)
                                        } else {
                                            return Double(videoVolume.userVolume)
                                        }
                                    },
                                    set: { newVal in
                                        let v = Float(newVal)
                                        if let id = currentAssetID {
                                            perVideoVolume = v
                                            Task { await VideoAudioOverrides.shared.setVolumeOverride(for: id, volume: v) }
                                        } else {
                                            videoVolume.userVolume = v
                                        }
                                    }
                                ), in: 0.0...1.0)
                                .tint(.accentColor)
                                .accessibilityLabel("Video volume")

                                let musicPlaying = FeatureFlags.enableAppleMusicIntegration ? music.isPlaying : false
                                let effective: Float = {
                                    let base: Float
                                    if let _ = currentAssetID, let local = perVideoVolume {
                                        base = local
                                    } else {
                                        base = videoVolume.userVolume
                                    }
                                    return musicPlaying ? min(base, videoVolume.duckingCapWhileMusic) : base
                                }()
                                Text(String(format: "%d%%", Int(round(Double(effective) * 100))))
                                    .foregroundColor(OptionsTheme.secondaryText)
                                    .font(.footnote.monospacedDigit())
                                    .frame(width: 44, alignment: .trailing)
                            }
                            if FeatureFlags.enableAppleMusicIntegration, music.isPlaying {
                                Text("Capped while music is playing.")
                                    .font(.caption2)
                                    .foregroundColor(OptionsTheme.secondaryText)
                            }
                        }
                        .padding(.top, 10)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Actions")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(OptionsTheme.text)
                            HStack(spacing: 12) {
                                if currentAssetID != nil {
                                    Button {
                                        onShare()
                                    } label: {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(OptionsTheme.text)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(minHeight: 44)
                                            .background(
                                                Capsule().fill(OptionsTheme.chipFill)
                                                    .overlay(Capsule().stroke(OptionsTheme.separator, lineWidth: 1))
                                            )
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Share current video")
                                }
                                Button {
                                    onOpenSettings()
                                } label: {
                                    Label("Settings", systemImage: "gearshape")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(OptionsTheme.text)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(minHeight: 44)
                                        .background(
                                            Capsule().fill(OptionsTheme.subtleFill)
                                                .overlay(Capsule().stroke(OptionsTheme.separator, lineWidth: 1))
                                        )
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open settings")
                            }
                        }
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 0)
                    .padding(.bottom, 8)
                }
                .padding(.bottom, 16 + bottomInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(OptionsTheme.background)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), stroke: false)
                        .ignoresSafeArea(edges: .bottom)
                )
                .background(
                    GeometryReader { gp in
                        Color.clear
                            .onAppear { panelHeight = gp.size.height }
                            .onChange(of: gp.size) { _, newSize in
                                panelHeight = newSize.height
                            }
                    }
                )
                .offset(y: yOffset)
                .opacity(reveal)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .local)
                        .onChanged { value in
                            guard value.translation.height > 0 else { return }
                            if !isClosingDrag {
                                isClosingDrag = true
                                options.beginCloseInteraction()
                            }
                            options.updateCloseDrag(dy: value.translation.height, distance: travel)
                        }
                        .onEnded { value in
                            guard isClosingDrag else { return }
                            options.endClose(velocityDown: value.velocity.y)
                            isClosingDrag = false
                        }
                )
            }
        }
        .allowsHitTesting(options.progress > 0.01)
        .onAppear {
            if let id = currentAssetID {
                Task {
                    perVideoVolume = await VideoAudioOverrides.shared.volumeOverride(for: id) ?? videoVolume.userVolume
                }
            } else {
                perVideoVolume = nil
            }
        }
        .onChange(of: currentAssetID) { _, newID in
            if let id = newID {
                Task {
                    let v = await VideoAudioOverrides.shared.volumeOverride(for: id)
                    await MainActor.run {
                        perVideoVolume = v ?? videoVolume.userVolume
                    }
                }
            } else {
                perVideoVolume = nil
            }
        }
    }
}

struct OptionsOpenHotspot: View {
    @ObservedObject var options: OptionsCoordinator

    private let hotspotSize = CGSize(width: 64, height: 180)
    private let hotspotLeadingOffset: CGFloat = 88
    private let hotspotBottomOffset: CGFloat = 36

    @State private var isInteracting = false
    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            let distance = openDistance(for: proxy.size)
            let reveal = clamp01(options.progress)
            let highlightOpacity = options.isPresented ? 0 : max(0, 1 - reveal * 2.5)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OptionsTheme.separator, lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(OptionsTheme.subtleFill)
                    )
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Drag up")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(OptionsTheme.secondaryText)
                        .padding(.vertical, 8)
                    }
                    .frame(width: hotspotSize.width, height: hotspotSize.height)
                    .opacity(highlightOpacity)
                    .scaleEffect(pulse ? 1.03 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: hotspotSize.width, height: hotspotSize.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .local)
                            .onChanged { value in
                                if !isInteracting, value.translation.height < 0 {
                                    isInteracting = true
                                    options.beginOpenInteraction()
                                }
                                guard isInteracting else { return }
                                options.updateOpenDrag(dy: value.translation.height, distance: distance)
                            }
                            .onEnded { value in
                                let vyUp = -value.velocity.y
                                options.endOpen(velocityUp: vyUp)
                                isInteracting = false
                            }
                    )
                    .accessibilityHidden(true)
            }
            .position(
                x: hotspotLeadingOffset + hotspotSize.width / 2,
                y: proxy.size.height - proxy.safeAreaInsets.bottom - hotspotBottomOffset - hotspotSize.height / 2
            )
        }
        .onAppear { pulse = true }
        .allowsHitTesting(!options.isPresented)
    }
}

struct OptionsDragHandle: View {
    @ObservedObject var options: OptionsCoordinator
    var openDistance: CGFloat? = nil
    @State private var isInteracting = false
    @State private var openDistanceCache: CGFloat = 360

    private let handleSize = CGSize(width: 26, height: 82)
    private let touchPadding = CGSize(width: 20, height: 18)

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.28))
                .frame(width: handleSize.width, height: handleSize.height)
                .liquidGlass(in: Capsule())
                .overlay(
                    Capsule().stroke(OptionsTheme.separator, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25 * clamp01(options.progress)), radius: 10 * clamp01(options.progress), x: 0, y: 6 * clamp01(options.progress))
        }
        .frame(width: handleSize.width, height: handleSize.height)
        .contentShape(Rectangle())
        .padding(.horizontal, touchPadding.width)
        .padding(.vertical, touchPadding.height)
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    if !isInteracting, value.translation.height < 0 {
                        isInteracting = true
                        options.beginOpenInteraction()
                    }
                    guard isInteracting else { return }
                    options.updateOpenDrag(dy: value.translation.height, distance: openDistanceCache)
                }
                .onEnded { value in
                    let vyUp = -value.velocity.y
                    options.endOpen(velocityUp: vyUp)
                    isInteracting = false
                }
        )
        .allowsHitTesting(!options.isPresented)
        .accessibilityLabel("Open panel")
        .onAppear {
            if let d = openDistance {
                openDistanceCache = d
            } else {
                openDistanceCache = min(max(UIScreen.main.bounds.size.height * 0.22, 280), 420)
            }
        }
        .onChange(of: openDistance) { _, newVal in
            if let d = newVal {
                openDistanceCache = d
            }
        }
    }
}

// Helpers

private func clamp01(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

private func targetPinnedHeight(for size: CGSize) -> CGFloat {
    let base = size.height * 0.32
    return min(max(base, 220), 360)
}

private func openDistance(for size: CGSize) -> CGFloat {
    min(max(size.height * 0.22, 280), 420)
}

private extension DragGesture.Value {
    var velocity: CGPoint {
        let dt: CGFloat = 0.016
        let dx = (predictedEndLocation.x - location.x) / dt
        let dy = (predictedEndLocation.y - location.y) / dt
        return CGPoint(x: dx, y: dy)
    }
}

private struct _HorizontalScrollWrap: ViewModifier {
    func body(content: Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                content
            }
        }
    }
}

private struct GlassCloseButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OptionsTheme.text)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .liquidGlass(in: Circle(), stroke: false)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}