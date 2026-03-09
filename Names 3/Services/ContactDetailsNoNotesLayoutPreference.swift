//
//  ContactDetailsNoNotesLayoutPreference.swift
//  Names 3
//
//  A/B test: what to show at the top of contact details when the contact has no notes.
//  Accessible via Settings → Usage → Contact details (no notes).
//

import SwiftUI

enum ContactDetailsNoNotesLayoutPreference: String, CaseIterable, Identifiable {
    case summaryFirst = "Summary First"
    case emptyStatePrompt = "Empty State Prompt"
    case addNoteBanner = "Add Note Banner"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .summaryFirst:
            return "Summary field only; notes section hidden when empty."
        case .emptyStatePrompt:
            return "ContentUnavailableView-style prompt; tap to focus QuickInput."
        case .addNoteBanner:
            return "Tappable \"Add your first note\" banner above summary."
        }
    }

    static let userDefaultsKey = "Names3.ContactDetailsNoNotesLayout"

    static var current: ContactDetailsNoNotesLayoutPreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let layout = ContactDetailsNoNotesLayoutPreference(rawValue: raw) else {
                return .summaryFirst
            }
            return layout
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
