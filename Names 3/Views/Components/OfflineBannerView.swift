//
//  OfflineBannerView.swift
//  Names 3
//
//  Polished banner shown when the device is offline. Airbnb-style: card shape, soft shadow, clear hierarchy. Dismissible; reappears when back online then offline again.
//

import SwiftUI

/// Banner displayed at the top when the app is offline. Use with safeAreaInset(edge: .top). Airbnb-style: rounded card, soft shadow, icon + title + supporting line.
struct OfflineBannerView: View {
    let isOffline: Bool
    /// When true, user has dismissed the banner for this session; still show again when coming back online then offline.
    var isDismissed: Bool = false
    var onDismiss: (() -> Void)? = nil

    private var shouldShow: Bool {
        isOffline && !isDismissed
    }

    var body: some View {
        if shouldShow {
            HStack(alignment: .center, spacing: 14) {
                iconView
                textStack
                Spacer(minLength: 4)
                if onDismiss != nil {
                    dismissButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(bannerBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
            }
            .padding(.horizontal, 12)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(String(localized: "offline.banner.title")). \(String(localized: "offline.banner.message"))"))
            .accessibilityHint(Text(String(localized: "offline.banner.hint")))
        }
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 40, height: 40)
            Image(systemName: "wifi.slash")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "offline.banner.title"))
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .label))
            Text(String(localized: "offline.banner.message"))
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var dismissButton: some View {
        Button {
            onDismiss?()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .frame(width: 28, height: 28)
                .background(Color(uiColor: .quaternarySystemFill))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var bannerBackground: some View {
        Color(uiColor: .secondarySystemGroupedBackground)
    }
}

/// Modifier to show an offline alert. Set showOfflineAlert = true when user triggers a network-dependent action while offline.
struct OfflineActionAlertModifier: ViewModifier {
    @Binding var showOfflineAlert: Bool
    var message: String = String(localized: "offline.alert.actionUnavailable")

    func body(content: Content) -> some View {
        content
            .alert(String(localized: "offline.alert.title"), isPresented: $showOfflineAlert) {
                Button(String(localized: "offline.alert.ok"), role: .cancel) {
                    showOfflineAlert = false
                }
            } message: {
                Text(message)
            }
    }
}

extension View {
    /// Presents the standard offline alert when showOfflineAlert is true. Set it to true when the user triggers a network-dependent action and ConnectivityMonitor.shared.isOffline is true.
    func offlineActionAlert(
        showOfflineAlert: Binding<Bool>,
        message: String = String(localized: "offline.alert.actionUnavailable")
    ) -> some View {
        modifier(OfflineActionAlertModifier(showOfflineAlert: showOfflineAlert, message: message))
    }
}

#Preview("Offline banner") {
    VStack(spacing: 0) {
        OfflineBannerView(isOffline: true, onDismiss: { })
        Spacer()
    }
}

#Preview("Offline banner dismissed") {
    OfflineBannerView(isOffline: true, isDismissed: true)
}
