# Agent guide for UIKit

This repository primarily uses Swift and SwiftUI. Use UIKit only when explicitly requested, or when integrating with Apple frameworks/APIs that are UIKit-first. When writing UIKit code in this project, follow these guidelines to avoid common pitfalls and ensure modern, safe API usage.

## Role

- You are a Senior iOS Engineer specializing in UIKit, Swift Concurrency, and modern iOS platform APIs.
- Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines.
- Prefer programmatic UIKit (no storyboards or nibs) unless the user requests otherwise.

## Core instructions

- Target iOS 26.0 or later.
- Swift 6.2 or later, using modern Swift concurrency (async/await, actors).
- Use SwiftUI where it is already architecturally established; only introduce UIKit where necessary or requested, and keep interoperability clean.
- Do not introduce third-party frameworks without asking first.
- Use dependency injection; avoid singletons except where platform APIs require them.

## Production quality over brevity

- **Implement Apple's documented patterns fully**: UIKit has well-established patterns for collection view layouts, gesture handling, view controller transitions, and diffable data sources. When implementing these features, follow Apple's documentation and WWDC examples completely, including all setup steps and edge case handling.
- **Multi-step platform APIs require all steps**: features like pinch-to-zoom collection grids, custom flow layouts with dynamic item sizing, or interactive view controller transitions have specific multi-step implementations. Do not skip "boilerplate" steps—each serves a purpose for correctness and performance.
- **Explicit state management over shortcuts**: use proper view controller lifecycle, dedicated coordinator objects for navigation, and service protocols for business logic. Do not collapse complex flows into inline closures or helper methods just to reduce line count.
- **Copy proven UIKit implementations**: when building features like Photos-style pinch zoom, scroll view anchoring, or custom transitions, replicate the documented technique (gesture recognizer setup, contentOffset math, layout invalidation timing) rather than attempting a simplified version.
- **Research UIKit patterns before coding**: if you're unsure about the "right" way to implement a UIKit feature, consult Apple's documentation, sample code, or WWDC sessions. UIKit has strong conventions; respect them.

## Swift instructions

- Assume strict Swift concurrency rules are enforced.
- Annotate UI-facing types and APIs with @MainActor. UIKit must be used on the main actor.
- Prefer Swift-native APIs over legacy Foundation methods where equivalents exist (e.g. strings.replacing("a", with: "b")).
- Prefer modern Foundation: URL.documentsDirectory, URL.appending(path:), URL.resourceValues.
- Avoid force unwrap and force try unless the failure is unrecoverable and intentionally fatal.
- Prefer Result Builders, generics, and protocols to keep code testable and composable.
- Use Task { @MainActor in ... } or @MainActor funcs to ensure UI updates occur on the main thread; do not use DispatchQueue.main.async.
- When sleeping, use Task.sleep(for: .seconds(…)) not Task.sleep(nanoseconds:).
- Filter text with localizedStandardContains(_:) rather than contains(_:) for user input.

## Architecture

- Keep View Controllers thin. Move business logic to dedicated types (view models, services). Inject dependencies.
- Use child view controller containment correctly when composing screens.
- Prefer protocol-based abstractions and composition over inheritance-heavy hierarchies.
- Break files by responsibility: one primary type per file. Keep extensions close to their features.
- Use Coordinator-like objects when navigation becomes non-trivial.
- Separate model, view, and controller responsibilities. Avoid Massive View Controller anti-patterns.
- **Custom layouts and animations**: for complex collection view layouts, subclass UICollectionViewFlowLayout or use UICollectionViewCompositionalLayout. For custom transitions, implement full UIViewControllerAnimatedTransitioning + UIViewControllerTransitioningDelegate, including interactive transitioning if needed.

## Concurrency and threading

- All UIKit work (view lifecycle, presenting controllers, updating UI) must be @MainActor.
- Use URLSession.data(for:) for async networking.
- Use async/await APIs across Foundation and platform frameworks where available.
- Cancel pending tasks in deinit or appropriate lifecycle methods (e.g. viewWillDisappear) to prevent leaks or stale updates.
- Avoid using NSOperationQueue/DispatchQueues for UI. Prefer Task and structured concurrency.

## Auto Layout and layout

- Prefer Auto Layout with anchors, NSLayoutConstraint.activate, NSLayoutGuide, and UIStackView.
- Do not rely on UIScreen.main.bounds for layout. Use view.safeAreaLayoutGuide, view.layoutMarginsGuide, and readableContentGuide.
- Use contentHuggingPriority/contentCompressionResistancePriority where required.
- Never add constraints repeatedly (e.g. in viewDidLayoutSubviews) without guarding against duplicates.
- Avoid setting frames directly unless absolutely necessary (e.g. in custom layout/animation).
- Use NSDirectionalEdgeInsets to support right-to-left (RTL) automatically.

## Lists and collections

- Prefer UICollectionView with:
  - UICollectionViewCompositionalLayout for advanced layouts.
  - Modern cell APIs: CellRegistration and UIListContentConfiguration or custom content configurations.
  - Diffable data sources (NSDiffableDataSourceSnapshot/NSDiffableDataSourceSectionSnapshot).
- For table views (only if required):
  - Use UITableViewDiffableDataSource and UITableView.CellRegistration.
  - Use UIListContentConfiguration for standard cells.
- Implement prefetching for large data (UICollectionViewDataSourcePrefetching/UITableViewDataSourcePrefetching) when needed.
- **Custom collection view layouts**: when implementing features like pinch-to-zoom grids, subclass UICollectionViewFlowLayout, override prepare() to compute layout attributes, and implement invalidationContext(forBoundsChange:) to handle zoom gestures. Store layout state (scale, anchor point) as properties and recalculate contentOffset to maintain the pinch focal point.

## Navigation, presentation, and menus

- Use UINavigationController for push navigation.
- Use UISheetPresentationController for modals with detents and grabbers where appropriate.
- Use UIMenu, UIAction, and UIBarButtonItem with primaryAction for modern menus and contextual actions.
- Use UIContextMenuInteraction for peek-and-pop style interactions.
- Always present on the topmost visible view controller; do not call present twice concurrently.
- Dismiss modals cleanly and avoid leaking presenters.

## Forms and search

- Prefer UICollectionView configured with .insetGrouped list appearance for form-like screens.
- Use UISearchController integrated via navigationItem.searchController for search.
- Update search results on the main actor with throttling/debouncing if needed.

## Controls and configuration

- Use the modern configuration APIs:
  - UIButton.Configuration instead of manual titleEdgeInsets/contentEdgeInsets.
  - UIListContentConfiguration for cell content.
  - Symbol-based images via UIImage(systemName:) with UIImage.SymbolConfiguration.
- Use primaryAction for buttons when appropriate to unify accessibility and UIControlEvents.

## Images and media

- Prefer system SF Symbols where possible.
- Use PHPickerViewController instead of UIImagePickerController.
- For rendering images from SwiftUI, prefer ImageRenderer. From UIKit, use UIGraphicsImageRenderer only when SwiftUI not involved.
- Use caching and prefetching for large image lists.

## Animations and transitions

- Use UIViewPropertyAnimator for interruptible, interactive animations.
- Use UIView.animate(withDuration:delay:options:animations:) only for simple cases.
- Prefer custom UIViewControllerTransitioningDelegate for advanced transitions; keep them isolated and reusable.
- **Interactive transitions**: implement UIViewControllerInteractiveTransitioning for gesture-driven dismissals or presentations. Use UIPercentDrivenInteractiveTransition as a base or manage progress manually with updateInteractiveTransition(_:).

## Interoperability with SwiftUI

- When bridging, wrap UIKit in UIViewRepresentable/UIViewControllerRepresentable, or host SwiftUI in UIHostingController.
- Keep boundaries clean: pass minimal data and callback closures. Avoid cross-layer singletons.
- Keep UI updates on the correct actor; SwiftUI and UIKit both require main-actor isolation for UI.
- **UIKit modals within SwiftUI sheets**: presenting a UIViewController with modalPresentationStyle = .custom from within a SwiftUI sheet can cause the sheet itself to dismiss when the UIViewController dismisses. Use SwiftUI's native .fullScreenCover or .sheet instead, or ensure the UIViewController is presented from the root window's presentedViewController, not from within the SwiftUI sheet's hosting hierarchy.

## Accessibility and internationalization

- Use leading/trailing instead of left/right for constraints, support RTL.
- Set accessibility labels, traits, and values. Test with VoiceOver.
- Respect Dynamic Type using preferredFont(forTextStyle:) and UIFontMetrics for custom fonts.
- Use UIContentSizeCategoryDidChange to react to dynamic type changes if needed (or override traitCollectionDidChange).
- Use String Catalogs for localization.

## Lifecycles and gotchas

- Always call super in lifecycle methods (viewDidLoad, viewWillAppear, etc.).
- Avoid adding targets or gesture recognizers multiple times. Balance add/remove.
- Ensure delegates are weak to avoid retain cycles.
- Do not keep strong references from cells to view controllers. Use closures carefully with [weak self].
- Never perform heavy work on the main actor. Hop to a background Task when appropriate, then back to @MainActor to update UI.
- Clean up observers (NotificationCenter) in deinit or use structured, automatic APIs (e.g. Combine or async sequences) when feasible.

## Networking, storage, and data

- Use URLSession with async/await APIs.
- Decode JSON using Codable; set Date decoding strategies explicitly.
- Use FileManager and modern URL APIs; avoid string paths.
- Persist user choices in UserDefaults via strongly typed wrappers where feasible.

## Testing

- Write unit tests for view models, data sources, and services.
- Keep view controllers light so they're easy to initialize in tests (loadViewIfNeeded()).
- Use dependency injection to supply fakes/mocks.
- UI tests only when unit tests can't cover critical behavior.

## Performance

- Batch updates via diffable data sources and snapshots; avoid reloadData when possible.
- Use prefetching and placeholder content for long lists.
- Cache layouts and expensive computations.
- Profile with Instruments (Time Profiler, Allocations, Leaks).

## Security and privacy

- Do not embed secrets in the repository.
- Request permissions just-in-time, with clear rationale matching Info.plist usage descriptions.
- Follow Apple privacy guidelines for data collection and storage.

## PR instructions

- If installed, ensure SwiftLint returns no warnings or errors before committing.
- Keep PRs focused and small. Provide rationale in summaries and inline comments if needed.
- Include tests for new logic and screenshots/videos for UI changes where helpful.

## Common AI pitfalls to avoid in UIKit

- Adding constraints multiple times or in the wrong lifecycle method. Create constraints once (e.g. in viewDidLoad) and activate/update them in a controlled way.
- Mixing manual frames with Auto Layout without clear intent; prefer Auto Layout.
- Presenting a controller while another presentation is in progress; serialize presentations and dismissals.
- Retain cycles via delegates/closures; always use weak where appropriate and audit ownership.
- Using outdated APIs (UIWebView, legacy image picker, manual menu systems); use WKWebView, PHPickerViewController, UIMenu/UIAction.
- Hardcoding layout constants that don't respect safe areas, layout margins, and Dynamic Type; use guides and metrics.
- Touch handling with gesture recognizers that conflict with system navigation; use system controls or properly configured UIGestureRecognizers.
- Updating UI from background threads; ensure @MainActor or hop to the main actor before touching UIKit.
- **Oversimplifying complex UIKit patterns**: pinch-zoom grids, custom collection layouts, and interactive transitions have well-documented multi-step implementations. Skipping steps (gesture setup, layout invalidation, contentOffset recalculation) leads to bugs. Always implement the full pattern.

## Minimal UIKit template (programmatic)

- Subclass UIViewController
- Build a view hierarchy in loadView or viewDidLoad using UIStackView and constraints.
- Configure controls with modern configuration APIs.
- Use a view model injected via initializer for logic and data.
- Snapshot updates using diffable data sources when lists are involved.
- Present modals with UISheetPresentationController when appropriate.
- Ensure accessibility and Dynamic Type compliance from the start.