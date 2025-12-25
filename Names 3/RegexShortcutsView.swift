import SwiftUI

struct RegexShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You can type multiple names and metadata in one go. These shortcuts are supported:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ShortcutRow(
                                title: "Separate names",
                                detail: "Use commas to separate names in one input.",
                                example: "Alex, Jamie, Pat"
                            )

                            ShortcutRow(
                                title: "Tags",
                                detail: "Add #tags anywhere to assign groups/places to all names.",
                                example: "#work #nyc"
                            )

                            ShortcutRow(
                                title: "Summary",
                                detail: "Add :: once to set a main summary for the entry.",
                                example: "Alex, Jamie :: Met at the conference"
                            )

                            ShortcutRow(
                                title: "Per‑name note",
                                detail: "Append : note after a name to attach that note to that person.",
                                example: "Pat: Tall, glasses"
                            )

                            ShortcutRow(
                                title: "Dates",
                                detail: "Include a date; the first detected date applies to all names.",
                                example: "Oct 12, 2024 or yesterday"
                            )

                            ShortcutRow(
                                title: "Quick save",
                                detail: "Press return to save all parsed contacts.",
                                example: "Press ⏎"
                            )
                        }
                        .padding(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let detail: String
    let example: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text(example)
                    .font(.callout.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer()
            }
        }
    }
}