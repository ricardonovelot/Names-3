import Foundation
import Photos
import CoreLocation

actor PhotoGroupingService {
    private let locationThreshold: CLLocationDistance = 20_000 // meters
    private let maxDayGap: Int = 7
    
    func groupAssets(_ assets: [PHAsset]) async -> [PhotoGroup] {
        guard !assets.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: assets) { asset -> Date in
            guard let date = asset.creationDate else { return Date.distantPast }
            return calendar.startOfDay(for: date)
        }
        
        var dayGroups: [(date: Date, assets: [PHAsset])] = groupedByDay.map { ($0.key, $0.value) }
            .sorted { $0.date > $1.date }
        
        var processed = Set<Date>()
        var mergedGroups: [[PHAsset]] = []
        
        for i in 0..<dayGroups.count {
            let (currentDate, currentAssets) = dayGroups[i]
            if processed.contains(currentDate) { continue }
            
            var groupToMerge = currentAssets
            processed.insert(currentDate)
            
            let currentLocations = currentAssets.compactMap { $0.location }
            let currentAvgLocation = currentLocations.isEmpty ? nil : averageLocation(currentLocations)
            
            for j in (i + 1)..<dayGroups.count {
                let (otherDate, otherAssets) = dayGroups[j]
                if processed.contains(otherDate) { continue }
                
                let dayDiff = abs(calendar.dateComponents([.day], from: currentDate, to: otherDate).day ?? 999)
                if dayDiff > maxDayGap { continue }
                
                let otherLocations = otherAssets.compactMap { $0.location }
                let otherAvgLocation = otherLocations.isEmpty ? nil : averageLocation(otherLocations)
                
                let shouldMerge: Bool
                if let currentLoc = currentAvgLocation, let otherLoc = otherAvgLocation {
                    let distance = currentLoc.distance(from: otherLoc)
                    shouldMerge = distance <= locationThreshold
                } else if currentAvgLocation == nil && otherAvgLocation == nil {
                    shouldMerge = true
                } else {
                    shouldMerge = false
                }
                
                if shouldMerge {
                    groupToMerge.append(contentsOf: otherAssets)
                    processed.insert(otherDate)
                }
            }
            
            mergedGroups.append(groupToMerge)
        }
        
        var groups: [PhotoGroup] = []
        groups.reserveCapacity(mergedGroups.count)
        
        for groupAssets in mergedGroups {
            let locations = groupAssets.compactMap { $0.location }
            let avgLocation = locations.isEmpty ? nil : averageLocation(locations)
            let group = await createPhotoGroup(from: groupAssets, location: avgLocation)
            groups.append(group)
        }
        
        return groups
    }
    
    private func averageLocation(_ locations: [CLLocation]) -> CLLocation? {
        guard !locations.isEmpty else { return nil }
        let avgLat = locations.map { $0.coordinate.latitude }.reduce(0, +) / Double(locations.count)
        let avgLon = locations.map { $0.coordinate.longitude }.reduce(0, +) / Double(locations.count)
        return CLLocation(latitude: avgLat, longitude: avgLon)
    }
    
    private func createPhotoGroup(from assets: [PHAsset], location: CLLocation?) async -> PhotoGroup {
        let representative = selectRepresentativePhotos(from: assets, count: 3)
        let date = assets.first?.creationDate ?? Date()
        return PhotoGroup(
            assets: assets,
            representativeAssets: representative,
            date: date,
            location: location,
            locationName: nil
        )
    }
    
    private func selectRepresentativePhotos(from assets: [PHAsset], count: Int) -> [PHAsset] {
        var scored: [(asset: PHAsset, score: Double)] = []
        scored.reserveCapacity(assets.count)
        
        for asset in assets {
            var score: Double = 0
            
            // Avoid screenshots
            if asset.mediaSubtypes.contains(.photoScreenshot) { score -= 1000 }
            
            if asset.isFavorite { score += 10 }
            
            let mediaSubtypes = asset.mediaSubtypes
            if mediaSubtypes.contains(.photoLive) { score += 2 }
            if mediaSubtypes.contains(.photoHDR) { score += 1 }
            if mediaSubtypes.contains(.photoPanorama) { score += 3 }
            
            if asset.location != nil { score += 3 }
            
            scored.append((asset, score))
        }
        
        let sorted = scored.sorted { $0.score > $1.score }
        return Array(sorted.prefix(count).map { $0.asset })
    }
}