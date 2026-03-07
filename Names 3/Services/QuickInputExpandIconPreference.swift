//
//  QuickInputExpandIconPreference.swift
//  Names 3
//
//  A/B test: which icon appears on the collapsed quick input bar (the circle that expands to add notes).
//  Accessible via Settings → Usage → Quick Input Icon.
//

import SwiftUI

enum QuickInputExpandIconPreference: String, CaseIterable, Identifiable {
    case plus = "Plus"
    case magnifyingglass = "Magnifying Glass"
    case pencil = "Pencil"
    case pencilCircle = "Pencil Circle"
    case pencilLine = "Pencil Line"
    case squareAndPencil = "Square & Pencil"
    case pencilTipCircle = "Pencil Tip Circle"
    case pencilAndOutline = "Pencil & Outline"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .plus: return "plus"
        case .magnifyingglass: return "magnifyingglass"
        case .pencil: return "pencil"
        case .pencilCircle: return "pencil.circle"
        case .pencilLine: return "pencil.line"
        case .squareAndPencil: return "square.and.pencil"
        case .pencilTipCircle: return "pencil.tip.crop.circle"
        case .pencilAndOutline: return "pencil.and.outline"
        }
    }

    static let userDefaultsKey = "Names3.QuickInputExpandIcon"

    static var current: QuickInputExpandIconPreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let icon = QuickInputExpandIconPreference(rawValue: raw) else { return .magnifyingglass }
            return icon
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
