# People Tab Toolbar — Root Cause Analysis

## Symptom
The People tab toolbar does not "sit on top" of the content like the Journal tab. Content does not scroll underneath the navigation bar.

## View Hierarchy Comparison

### Journal Tab (works correctly)
```
JournalTabView
└── NavigationStack
    └── List { ... }           ← SwiftUI native scroll view
        .navigationTitle("Recalled Gratitude")
        .toolbar { compose button }
```
- **Content**: SwiftUI `List`
- **Behavior**: List extends into the nav bar region; content scrolls underneath with proper insets
- **Result**: Toolbar floats on top, content scrolls beneath

### People Tab (problematic)
```
ContentView > ZStack > People Group
└── NavigationStack
    └── Group
        └── PeopleTabView
            └── contactsContent() = listAndPhotosContent
                └── ContactsFeedView
                    └── ContactsFeedViewControllerRepresentable
                        └── ContactsFeedViewController (UIKit)
                            └── UICollectionView
```
- **Content**: UIKit `UICollectionView` via `UIViewControllerRepresentable`
- **Behavior**: When SwiftUI hosts a UIViewController, the view is laid out in the *content area* — the rect *below* the navigation bar. The UIKit view does not extend into the bar region.
- **Result**: Bar and content are adjacent; content starts below the bar; no scroll-under effect

## Root Cause
**The People tab uses UIKit (UICollectionView) while Journal uses SwiftUI (List).**

SwiftUI scroll views (List, ScrollView) participate in the navigation bar's content-inset coordination. They extend into the bar region and scroll content underneath. UIKit views embedded via `UIViewControllerRepresentable` are laid out in the safe area — they do not extend under the bar.

## Fix
Make the People scroll content extend under the top safe area so it can scroll beneath the bar:

1. Add `.ignoresSafeArea(.container, edges: .top)` to the People tab's scroll content
2. The UICollectionView already has `contentInsetAdjustmentBehavior = .always` — it will add top content inset so the first row is not hidden under the bar
3. When scrolling, content will pass underneath the toolbar, matching Journal's behavior

## Files to Modify
- `ContentView.swift`: Add `.ignoresSafeArea(.container, edges: .top)` to the People content Group
- Optionally verify `ContactsFeedViewController` — `contentInsetAdjustmentBehavior = .always` is correct for this
