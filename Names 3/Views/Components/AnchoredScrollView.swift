import SwiftUI
import UIKit

@MainActor
struct AnchoredScrollView<Content: View>: UIViewRepresentable {
    @Binding var isAtBottom: Bool
    var bottomInset: CGFloat
    @ViewBuilder var content: () -> Content

    init(isAtBottom: Binding<Bool>, bottomInset: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self._isAtBottom = isAtBottom
        self.bottomInset = bottomInset
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isAtBottom: _isAtBottom, externalBottomInset: bottomInset)
    }

    func makeUIView(context: Context) -> ObservingScrollView {
        let scroll = ObservingScrollView()
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = true
        scroll.keyboardDismissMode = .interactive
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator
        scroll.onDidLayout = { [weak coordinator = context.coordinator] in
            coordinator?.handleContentChange()
        }

        let hosting = UIHostingController(rootView: content())
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .systemGroupedBackground

        context.coordinator.hosting = hosting
        context.coordinator.scrollView = scroll

        scroll.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            hosting.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        context.coordinator.startObservingKeyboard()
        context.coordinator.updateInsets()
        // Start anchored at bottom
        context.coordinator.scrollToBottom(animated: false)
        return scroll
    }

    func updateUIView(_ uiView: ObservingScrollView, context: Context) {
        context.coordinator.externalBottomInset = bottomInset
        context.coordinator.updateInsets()

        if let hosting = context.coordinator.hosting {
            hosting.rootView = content()
        }
        // Do not force layout here; the scroll subclass will notify on the next layout pass.
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hosting: UIHostingController<Content>?
        weak var scrollView: UIScrollView?

        @Binding var isAtBottomBinding: Bool
        private(set) var isAnchored: Bool
        var externalBottomInset: CGFloat
        private var keyboardInset: CGFloat = 0
        private var lastContentHeight: CGFloat = 0
        private var isUserInteracting = false

        init(isAtBottom: Binding<Bool>, externalBottomInset: CGFloat) {
            self._isAtBottomBinding = isAtBottom
            self.isAnchored = isAtBottom.wrappedValue
            self.externalBottomInset = externalBottomInset
        }

        func startObservingKeyboard() {
            NotificationCenter.default.addObserver(self, selector: #selector(onKeyboardChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(onKeyboardChange(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func onKeyboardChange(_ note: Notification) {
            guard let scrollView else { return }
            var height: CGFloat = 0
            if let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let local = scrollView.convert(endFrame, from: nil)
                let intersection = scrollView.bounds.intersection(local)
                height = max(0, intersection.height - scrollView.safeAreaInsets.bottom)
            }
            keyboardInset = height
            updateInsets()

            if isAnchored && !isUserInteracting {
                scrollToBottom(animated: true)
            }
        }

        func updateInsets() {
            guard let scrollView else { return }
            let bottom = max(externalBottomInset, keyboardInset)
            var inset = scrollView.contentInset
            inset.bottom = bottom
            scrollView.contentInset = inset
            var indicators = scrollView.verticalScrollIndicatorInsets
            indicators.bottom = bottom
            scrollView.verticalScrollIndicatorInsets = indicators
        }

        func handleContentChange() {
            guard let scrollView else { return }
            let height = scrollView.contentSize.height
            let changed = abs(height - lastContentHeight) > 0.5
            defer { lastContentHeight = height }

            guard changed else { return }

            if isAnchored && !isUserInteracting {
                scrollToBottom(animated: false)
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserInteracting = true
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                isUserInteracting = false
                updateAnchoredStateIfNeeded(scrollView)
            }
        }

        func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
            isUserInteracting = true
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserInteracting = false
            updateAnchoredStateIfNeeded(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let atBottom = isNearBottom(scrollView)
            if atBottom != isAtBottomBinding {
                isAtBottomBinding = atBottom
            }
            // Do not flip anchoring while interacting to avoid momentum pauses.
            if !isUserInteracting {
                isAnchored = atBottom
            }
        }

        private func updateAnchoredStateIfNeeded(_ scrollView: UIScrollView) {
            let atBottom = isNearBottom(scrollView)
            isAnchored = atBottom
            if isAnchored {
                scrollToBottom(animated: false)
            }
        }

        private func isNearBottom(_ scrollView: UIScrollView) -> Bool {
            let epsilon: CGFloat = 1
            let bottomY = max(-scrollView.adjustedContentInset.top,
                              scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
            return scrollView.contentOffset.y >= bottomY - epsilon
        }

        func scrollToBottom(animated: Bool) {
            guard let scrollView else { return }
            let targetY = max(-scrollView.adjustedContentInset.top,
                              scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
            let target = CGPoint(x: -scrollView.adjustedContentInset.left, y: targetY)
            if animated {
                UIView.animate(withDuration: 0.22) {
                    scrollView.setContentOffset(target, animated: false)
                }
            } else {
                scrollView.setContentOffset(target, animated: false)
            }
        }
    }
}

final class ObservingScrollView: UIScrollView {
    var onDidLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onDidLayout?()
    }
}