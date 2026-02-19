import SwiftUI
import UIKit

@MainActor
struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    let excludedActivityTypes: [UIActivity.ActivityType]?
    let detents: [UISheetPresentationController.Detent]
    let completion: UIActivityViewController.CompletionWithItemsHandler?

    final class Coordinator {
        var controller: UIActivityViewController?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.isHidden = true
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        if isPresented, context.coordinator.controller == nil, !activityItems.isEmpty {
            let vc = UIActivityViewController(activityItems: activityItems,
                                              applicationActivities: applicationActivities)
            vc.excludedActivityTypes = excludedActivityTypes

            if let sheet = vc.sheetPresentationController {
                sheet.detents = detents
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            }

            vc.completionWithItemsHandler = { activityType, completed, items, error in
                completion?(activityType, completed, items, error)
                self.isPresented = false
                context.coordinator.controller = nil
            }

            if let pop = vc.popoverPresentationController {
                pop.sourceView = host.view
                pop.sourceRect = CGRect(x: host.view.bounds.midX,
                                        y: host.view.bounds.maxY,
                                        width: 1, height: 1)
                pop.permittedArrowDirections = []
            }

            host.present(vc, animated: true)
            context.coordinator.controller = vc
        } else if !isPresented, let presented = context.coordinator.controller {
            presented.dismiss(animated: true)
            context.coordinator.controller = nil
        }
    }
}

extension View {
    func systemShareSheet(
        isPresented: Binding<Bool>,
        items: [Any],
        applicationActivities: [UIActivity]? = nil,
        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
        detents: [UISheetPresentationController.Detent] = [.medium(), .large()],
        onComplete: UIActivityViewController.CompletionWithItemsHandler? = nil
    ) -> some View {
        background(
            ShareSheetPresenter(
                isPresented: isPresented,
                activityItems: items,
                applicationActivities: applicationActivities,
                excludedActivityTypes: excludedActivityTypes,
                detents: detents,
                completion: onComplete
            )
        )
    }
}