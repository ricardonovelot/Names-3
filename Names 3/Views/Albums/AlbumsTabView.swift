//
//  AlbumsTabView.swift
//  Names 3
//
//  SwiftUI bridge for the Albums tab. Wraps AlbumsProfileViewController in a
//  UINavigationController so album grid → detail push navigation works.
//

import SwiftUI
import UIKit

// MARK: - AlbumsTabView

struct AlbumsTabView: View {
    var bottomBarHeight: CGFloat = 0

    var body: some View {
        AlbumsTabRepresentable(bottomBarHeight: max(bottomBarHeight, tabBarMinimumHeight))
            .ignoresSafeArea()
    }
}

// MARK: - UIViewControllerRepresentable

private struct AlbumsTabRepresentable: UIViewControllerRepresentable {
    let bottomBarHeight: CGFloat

    func makeUIViewController(context: Context) -> UINavigationController {
        let profile = AlbumsProfileViewController()
        profile.bottomBarHeight = bottomBarHeight
        let nav = UINavigationController(rootViewController: profile)
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        if let profile = nav.viewControllers.first as? AlbumsProfileViewController {
            profile.bottomBarHeight = bottomBarHeight
        }
    }
}
