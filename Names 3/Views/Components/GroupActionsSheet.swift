import SwiftUI

struct GroupActionsSheet: View {
    let date: Date
    let onImport: () -> Void
    let onEditDate: () -> Void
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date, style: .date)
                            .font(.title3.weight(.semibold))
                        Text(relativeString(for: date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        isBusy = true
                        onImport()
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Import photos for this day")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isBusy = true
                        onEditDate()
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                            Text("Edit date")
                            Spacer()
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 8)
                }
                .padding()

                if isBusy {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .navigationTitle("Group")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func relativeString(for date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}