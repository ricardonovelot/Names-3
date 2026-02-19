//
//  MainTabView.swift
//  Names 3
//
//  Apple Music–style: collapsed = circle icon, expanded = full input bar. Same horizontal stack.
//

import SwiftUI

enum MainTab: Int, CaseIterable {
    case nameFaces = 0   // combined: feed + face-naming carousel
    case people = 1      // people middle
    case practice = 2    // practice third

    var title: String {
        switch self {
        case .people: return String(localized: "tab.people")
        case .practice: return String(localized: "tab.practice")
        case .nameFaces: return String(localized: "tab.nameFaces")
        }
    }

    var icon: String {
        switch self {
        case .people: return "person.2.fill"
        case .practice: return "rectangle.stack.fill"
        case .nameFaces: return "camera.fill"
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

// MARK: - Apple Music–Style Tab Bar

/// [Name Faces] [People] [Practice] pill + [○] circle. Two separate containers, no nested bubble.
struct QuickInputBottomBar<InlineInputContent: View>: View {
    @Binding var selectedTab: MainTab
    @Binding var isQuickInputExpanded: Bool
    var canShowQuickInput: Bool
    var showNameFacesButton: Bool = true
    var onNameFacesTap: (() -> Void)? = nil
    @ViewBuilder var inlineInputContent: () -> InlineInputContent

    private let barSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    var body: some View {
        HStack(spacing: 0) {
            if isQuickInputExpanded {
                expandedBar
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.2, anchor: .trailing).combined(with: .opacity),
                        removal: .scale(scale: 0.2, anchor: .trailing).combined(with: .opacity)
                    ))
            } else {
                collapsedBar
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity),
                        removal: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity)
                    ))
            }
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
                if showNameFacesButton, onNameFacesTap != nil {
                    cameraBubble
                }
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
            withAnimation(barSpring) {
                isQuickInputExpanded = false
            }
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

    /// Camera inside the input pill (not a separate bubble).
    private var cameraBubble: some View {
        Button {
            onNameFacesTap?()
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    /// Two separate containers: [tabs pill] [search circle]. No inner bubble on active tab.
    private var collapsedBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(MainTab.allCases, id: \.rawValue) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .liquidGlass(in: .rect(cornerRadius: 28), stroke: true, style: .translucent)
            .frame(maxWidth: 400)

            if canShowQuickInput {
                expandButton
                    .transition(.opacity)
            }
        }
    }

    /// Glass lens icon in its own bubble. Same height as tabs pill.
    private var expandButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred(intensity: 0.6)
            withAnimation(barSpring) {
                isQuickInputExpanded = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedTab = tab
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

private struct TabBarButtonStyle: ButtonStyle {
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
                    canShowQuickInput: true,
                    showNameFacesButton: true,
                    onNameFacesTap: {}
                ) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                Text("Add note…")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
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
