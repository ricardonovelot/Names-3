//
//  MainTabView.swift
//  Names 3
//
//  Apple Music–style: collapsed = circle icon, expanded = full input bar. Same horizontal stack.
//

import SwiftUI
import os

enum MainTab: Int, CaseIterable {
    case photos = 0      // combined: feed + face-naming carousel (was Name Faces)
    case people = 1
    case journal = 2
    case practice = 3    // accessed via People toolbar menu, not shown in tab bar
    case albums = 4

    /// Tabs shown in the tab bar (Practice is in People toolbar menu).
    static var tabBarTabs: [MainTab] { [.photos, .albums, .people, .journal] }

    var title: String {
        switch self {
        case .photos: return String(localized: "tab.photos")
        case .people: return String(localized: "tab.people")
        case .journal: return String(localized: "tab.journal")
        case .practice: return String(localized: "tab.practice")
        case .albums: return String(localized: "tab.albums")
        }
    }

    var icon: String {
        switch self {
        case .photos: return "photo.stack.fill"
        case .people: return "person.2.fill"
        case .journal: return "sparkles"
        case .practice: return "rectangle.stack.fill"
        case .albums: return "square.stack.fill"
        }
    }
}

// MARK: - Tab Bar Height Preference

/// Preference key for the tab bar's height. Used by Name Faces to add bottom inset so the carousel doesn't overlap the bar.
enum TabBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Minimum height to reserve for the tab bar when measured height isn't available yet (pill 64pt + padding 16pt).
let tabBarMinimumHeight: CGFloat = 80

private let tabBarLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "TabBar")

// MARK: - Apple Music–Style Tab Bar

/// [Name Faces] [People] [Practice] pill + [○] circle. Two separate containers, no nested bubble.
struct QuickInputBottomBar<InlineInputContent: View>: View {
    @Binding var selectedTab: MainTab
    @Binding var isQuickInputExpanded: Bool
    var canShowQuickInput: Bool
    /// When true (feed or albums tab), show music button instead of quick input expand button.
    var showMusicButtonInsteadOfQuickInput: Bool = false
    var onMusicTapped: (() -> Void)? = nil
    var musicButtonDisabled: Bool = false
    /// Called when user taps the already-selected tab (native bar behavior: scroll to top).
    var onSameTabTapped: ((MainTab) -> Void)? = nil
    @AppStorage(QuickInputExpandIconPreference.userDefaultsKey) private var expandIconRaw: String = QuickInputExpandIconPreference.magnifyingglass.rawValue
    @ViewBuilder var inlineInputContent: () -> InlineInputContent

    @State private var pendingCollapseWorkItem: DispatchWorkItem?

    private let barSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    var body: some View {
        ZStack(alignment: .leading) {
            collapsedBar
                .opacity(isQuickInputExpanded ? 0 : 1)
                .allowsHitTesting(!isQuickInputExpanded)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity),
                    removal: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity)
                ))
            expandedBar
                .opacity(isQuickInputExpanded ? 1 : 0)
                .allowsHitTesting(isQuickInputExpanded)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.2, anchor: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
        }
        .frame(maxWidth: .infinity)
        .animation(barSpring, value: isQuickInputExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedTab)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom, 8)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: TabBarHeightPreferenceKey.self, value: geo.size.height)
            }
        )
    }

    /// Chevron in its own separate circle; input in its own pill. Two distinct containers with gap.
    private var expandedBar: some View {
        HStack(spacing: 10) {
            collapseButton

            HStack(spacing: 6) {
                inlineInputContent()
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .liquidGlass(in: .rect(cornerRadius: 28), stroke: true, style: .translucent)
        }
    }

    /// Selected tab in its own bubble; tap to collapse.
    private var collapseButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred(intensity: 0.6)
            pendingCollapseWorkItem?.cancel()
            let work = DispatchWorkItem {
                tabBarLogger.debug("Executing delayed collapse")
                NotificationCenter.default.post(name: .quickInputLockFocus, object: nil)
                withAnimation(barSpring) {
                    isQuickInputExpanded = false
                }
            }
            pendingCollapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: work)
        } label: {
            Image(systemName: selectedTab.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: pillHeight, height: pillHeight)
                .liquidGlass(in: Circle(), stroke: true, style: .translucent)
                .contentShape(Circle())
        }
        .buttonStyle(TabBarButtonStyle())
        .accessibilityLabel(selectedTab.title)
    }

    /// Two separate containers: [tabs pill] [search circle]. No inner bubble on active tab.
    private var collapsedBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(MainTab.tabBarTabs, id: \.rawValue) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .liquidGlass(in: .rect(cornerRadius: 28), stroke: true, style: .translucent)
            .frame(maxWidth: 400)

            if showMusicButtonInsteadOfQuickInput {
                musicButton
                    .transition(.opacity)
            } else if canShowQuickInput {
                expandButton
                    .transition(.opacity)
            }
        }
    }

    /// Music note icon in its own bubble. Shown on feed and albums tabs instead of quick input.
    private var musicButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred(intensity: 0.6)
            onMusicTapped?()
        } label: {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: pillHeight, height: pillHeight)
                .liquidGlass(in: Circle(), stroke: true, style: .translucent)
                .contentShape(Circle())
        }
        .buttonStyle(TabBarButtonStyle())
        .disabled(musicButtonDisabled)
        .accessibilityLabel("Assign music")
    }

    /// Glass lens icon in its own bubble. Same height as tabs pill.
    private var expandButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred(intensity: 0.6)
            pendingCollapseWorkItem?.cancel()
            pendingCollapseWorkItem = nil
            tabBarLogger.debug("Expand tapped, cancelled any pending collapse")
            NotificationCenter.default.post(name: .quickInputLockFocus, object: nil)
            withAnimation(barSpring) {
                isQuickInputExpanded = true
            }
        } label: {
            Image(systemName: (QuickInputExpandIconPreference(rawValue: expandIconRaw) ?? .magnifyingglass).systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: pillHeight, height: pillHeight)
                .liquidGlass(in: Circle(), stroke: true, style: .translucent)
                .contentShape(Circle())
        }
        .buttonStyle(TabBarButtonStyle())
        .accessibilityLabel("Add note")
    }

    private let tabItemHeight: CGFloat = 48
    private var pillHeight: CGFloat { tabItemHeight + 16 }

    @ViewBuilder
    private func tabButton(_ tab: MainTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred(intensity: 0.6)
            if isSelected {
                onSameTabTapped?(tab)
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: tabItemHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabBarButtonStyle())
        .accessibilityLabel(tab.title)
    }
}

struct TabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("QuickInputBottomBar") {
    struct PreviewWrapper: View {
        @State private var selectedTab: MainTab = .people
        @State private var isExpanded = false
        var body: some View {
            VStack {
                Spacer()
                QuickInputBottomBar(
                    selectedTab: $selectedTab,
                    isQuickInputExpanded: $isExpanded,
                    canShowQuickInput: true
                ) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            HStack(spacing: 8) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                                Text("Add note…")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                        )
                        .frame(height: 40)
                }
                .padding(.bottom, 20)
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
    return PreviewWrapper()
}
