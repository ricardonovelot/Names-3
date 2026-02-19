import Foundation
import Combine

@MainActor
final class CurrentPlayback: ObservableObject {
    static let shared = CurrentPlayback()
    @Published var currentAssetID: String?
    private init() {}
}