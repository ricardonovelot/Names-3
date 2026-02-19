import SwiftUI

struct DownloadOverlayView: View {
    @ObservedObject private var tracker = DownloadTracker.shared
    @ObservedObject private var playback = CurrentPlayback.shared

    private var averageRatePercentPerSec: Double? {
        let rates = tracker.entries.filter { !$0.isComplete && !$0.isFailed }.compactMap { $0.progressRatePercentPerSec }
        guard !rates.isEmpty else { return nil }
        let sum = rates.reduce(0, +)
        return sum / Double(rates.count)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Active: \(tracker.entries.filter { !$0.isComplete && !$0.isFailed }.count)")
                    .font(.caption)
                if let avg = averageRatePercentPerSec, avg.isFinite {
                    Text(String(format: "Avg: %.1f%%/s", avg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Downloads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            
            Divider().opacity(0.25)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(tracker.entries) { e in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shortID(e.id))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(e.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundStyle(e.isFailed ? .red : .primary)
                                    if let note = e.note, !note.isEmpty {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if e.isComplete {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text("Ready")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                } else {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(Int(e.progress * 100))%")
                                            .font(.caption2)
                                            .monospacedDigit()
                                        if let r = e.progressRatePercentPerSec, r.isFinite {
                                            Text(String(format: "%.1f%%/s", r))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .id(e.id)
                            .padding(6)
                            .background(playback.currentAssetID == e.id ? Color.white.opacity(0.08) : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 160)
                .onAppear {
                    if let current = playback.currentAssetID {
                        withAnimation {
                            proxy.scrollTo(current, anchor: .center)
                        }
                    }
                }
                .onChange(of: playback.currentAssetID) { _, current in
                    if let current {
                        withAnimation {
                            proxy.scrollTo(current, anchor: .center)
                        }
                    }
                }
                .onChange(of: tracker.entries.map(\.id)) { _, _ in
                    if let current = playback.currentAssetID {
                        withAnimation {
                            proxy.scrollTo(current, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: playback.currentAssetID)
    }
    
    private func shortID(_ id: String) -> String {
        if id.count <= 6 { return id }
        let start = id.prefix(4)
        let end = id.suffix(3)
        return "\(start)…\(end)"
    }
}