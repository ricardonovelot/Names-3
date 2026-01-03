import Photos
import Foundation

// MARK: - Sampling Strategy

enum SamplingStrategy {
    case none              // Show all photos (normal zoom)
    case perDay            // 1 photo per day (zoomed out)
    case perWeek           // 1 photo per week (very zoomed out)
    case perMonth          // 1 photo per month (extremely zoomed out)
    
    static func strategy(for columnCount: Int) -> SamplingStrategy {
        switch columnCount {
        case ...4:
            return .none
        case 5...8:
            return .perDay
        case 9...14:
            return .perWeek
        default:
            return .perMonth
        }
    }
}

// MARK: - Photo Sampling Service

final class PhotoSamplingService {
    static let shared = PhotoSamplingService()
    
    private init() {}
    
    // MARK: - Public API
    
    func sample(_ assets: [PHAsset], strategy: SamplingStrategy) -> [PHAsset] {
        guard !assets.isEmpty else { return [] }
        
        switch strategy {
        case .none:
            return assets
        case .perDay:
            return samplePerDay(assets)
        case .perWeek:
            return samplePerWeek(assets)
        case .perMonth:
            return samplePerMonth(assets)
        }
    }
    
    // MARK: - Sampling Implementations
    
    private func samplePerDay(_ assets: [PHAsset]) -> [PHAsset] {
        var seenDays = Set<String>()
        var sampled: [PHAsset] = []
        
        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let dayKey = dayIdentifier(for: date)
            
            if seenDays.insert(dayKey).inserted {
                sampled.append(selectBestAsset(from: assets, forDay: date) ?? asset)
            }
        }
        
        return sampled
    }
    
    private func samplePerWeek(_ assets: [PHAsset]) -> [PHAsset] {
        var seenWeeks = Set<String>()
        var sampled: [PHAsset] = []
        
        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let weekKey = weekIdentifier(for: date)
            
            if seenWeeks.insert(weekKey).inserted {
                sampled.append(selectBestAsset(from: assets, forWeek: date) ?? asset)
            }
        }
        
        return sampled
    }
    
    private func samplePerMonth(_ assets: [PHAsset]) -> [PHAsset] {
        var seenMonths = Set<String>()
        var sampled: [PHAsset] = []
        
        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let monthKey = monthIdentifier(for: date)
            
            if seenMonths.insert(monthKey).inserted {
                sampled.append(selectBestAsset(from: assets, forMonth: date) ?? asset)
            }
        }
        
        return sampled
    }
    
    // MARK: - Best Asset Selection
    
    private func selectBestAsset(from assets: [PHAsset], forDay date: Date) -> PHAsset? {
        let calendar = Calendar.current
        let dayAssets = assets.filter { asset in
            guard let assetDate = asset.creationDate else { return false }
            return calendar.isDate(assetDate, inSameDayAs: date)
        }
        
        return selectBest(from: dayAssets)
    }
    
    private func selectBestAsset(from assets: [PHAsset], forWeek date: Date) -> PHAsset? {
        let calendar = Calendar.current
        let weekAssets = assets.filter { asset in
            guard let assetDate = asset.creationDate else { return false }
            return calendar.isDate(assetDate, equalTo: date, toGranularity: .weekOfYear)
        }
        
        return selectBest(from: weekAssets)
    }
    
    private func selectBestAsset(from assets: [PHAsset], forMonth date: Date) -> PHAsset? {
        let calendar = Calendar.current
        let monthAssets = assets.filter { asset in
            guard let assetDate = asset.creationDate else { return false }
            return calendar.isDate(assetDate, equalTo: date, toGranularity: .month)
        }
        
        return selectBest(from: monthAssets)
    }
    
    private func selectBest(from assets: [PHAsset]) -> PHAsset? {
        guard !assets.isEmpty else { return nil }
        
        // Priority 1: Favorites
        if let favorite = assets.first(where: { $0.isFavorite }) {
            return favorite
        }
        
        // Priority 2: Burst key photos
        if let keyPhoto = assets.first(where: { $0.representsBurst && $0.burstSelectionTypes.contains(.userPick) }) {
            return keyPhoto
        }
        
        // Priority 3: Non-screenshots
        let nonScreenshots = assets.filter { asset in
            !asset.mediaSubtypes.contains(.photoScreenshot)
        }
        
        if !nonScreenshots.isEmpty {
            // Priority 4: Panoramas, Live Photos (more interesting)
            if let panorama = nonScreenshots.first(where: { $0.mediaSubtypes.contains(.photoPanorama) }) {
                return panorama
            }
            
            if let livePhoto = nonScreenshots.first(where: { $0.mediaSubtypes.contains(.photoLive) }) {
                return livePhoto
            }
            
            // Priority 5: First non-screenshot
            return nonScreenshots.first
        }
        
        // Fallback: Just return the first asset
        return assets.first
    }
    
    // MARK: - Date Identifiers
    
    private func dayIdentifier(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
    
    private func weekIdentifier(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }
    
    private func monthIdentifier(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }
}