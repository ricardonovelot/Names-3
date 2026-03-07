//
//  LowStorageBannerView.swift
//  Names 3
//
//  Banner shown when device storage is low. Items may fail to load. Dismissible.
//

import SwiftUI

struct LowStorageBannerView: View {
    let isLowStorage: Bool
    var isDismissed: Bool = false
    var onDismiss: (() -> Void)? = nil

    private var shouldShow: Bool {
        isLowStorage && !isDismissed
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
            .accessibilityLabel(Text("\(String(localized: "storage.banner.title")). \(String(localized: "storage.banner.message"))"))
        }
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 40, height: 40)
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "storage.banner.title"))
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .label))
            Text(String(localized: "storage.banner.message"))
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
