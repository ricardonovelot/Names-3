import Foundation
import Photos
import CoreLocation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names", category: "PhotoGrouping")

actor PhotoGroupingService {
    private let locationThreshold: CLLocationDistance = 20_000
    private let maxDayGap: Int = 7
    
    func groupAssets(_ assets: [PHAsset]) async -> [PhotoGroup] {
        guard !assets.isEmpty else { return [] }
        
        logger.info("groupAssets started with \(assets.count) assets")
        print("🔄 Grouping \(assets.count) assets...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: assets) { asset -> Date in
            guard let date = asset.creationDate else { return Date.distantPast }
            return calendar.startOfDay(for: date)
        }
        
        logger.debug("Grouped into \(groupedByDay.count) days")
        print("📅 Initial grouping: \(groupedByDay.count) days")
        
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
        
        logger.debug("Merged into \(mergedGroups.count) groups")
        print("🔗 After merging: \(mergedGroups.count) groups")
        
        var groups: [PhotoGroup] = []
        groups.reserveCapacity(mergedGroups.count)
        
        for (index, groupAssets) in mergedGroups.enumerated() {
            let locations = groupAssets.compactMap { $0.location }
            let avgLocation = locations.isEmpty ? nil : averageLocation(locations)
            let date = groupAssets.first?.creationDate ?? Date()
            let representative = selectRepresentativePhotos(from: groupAssets, count: 3)
            let id = PhotoGroup.makeID(date: date, location: avgLocation)
            let group = PhotoGroup(
                id: id,
                assets: groupAssets,
                representativeAssets: representative,
                date: date,
                location: avgLocation,
                locationName: nil
            )
            groups.append(group)
            
            if index < 3 || index >= mergedGroups.count - 3 {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM dd, yyyy"
                print("  Group \(index): \(formatter.string(from: date)) - \(groupAssets.count) assets")
            } else if index == 3 {
                print("  ... (\(mergedGroups.count - 6) more groups) ...")
            }
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("groupAssets completed: \(groups.count) groups in \(String(format: "%.3f", duration))s")
        print("✅ Grouping done: \(groups.count) groups in \(String(format: "%.3f", duration))s")
        print("📅 Date range: \(groups.last?.title ?? "?") (oldest) → \(groups.first?.title ?? "?") (newest)")
        
        return groups
    }
    
    private func averageLocation(_ locations: [CLLocation]) -> CLLocation? {
        guard !locations.isEmpty else { return nil }
        let avgLat = locations.map { $0.coordinate.latitude }.reduce(0, +) / Double(locations.count)
        let avgLon = locations.map { $0.coordinate.longitude }.reduce(0, +) / Double(locations.count)
        return CLLocation(latitude: avgLat, longitude: avgLon)
    }
    
    private func selectRepresentativePhotos(from assets: [PHAsset], count: Int) -> [PHAsset] {
        var scored: [(asset: PHAsset, score: Double)] = []
        scored.reserveCapacity(assets.count)
        
        for asset in assets {
            var score: Double = 0
            
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