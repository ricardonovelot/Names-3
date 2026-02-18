import SwiftUI

/// Quick input usage guide. Shown from Settings (pushed); no own NavigationStack.
struct QuickInputGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Add several people in one line using the bar at the bottom. These shortcuts are supported:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                GuideSection(title: "Names") {
                    ShortcutRow(
                        title: "Multiple names",
                        detail: "Separate names with commas. All get the same date and tags unless you override per name.",
                        example: "Alex, Jamie, Pat"
                    )
                }

                GuideSection(title: "Summary & notes") {
                    ShortcutRow(
                        title: "Summary for everyone",
                        detail: "Use :: once to set a shared summary for all names in the line.",
                        example: "Alex, Jamie :: Met at the conference"
                    )
                    ShortcutRow(
                        title: "Note for one person",
                        detail: "Put : and a note after a name to attach it only to that person.",
                        example: "Pat: Tall, wears glasses"
                    )
                }

                GuideSection(title: "Groups & places") {
                    ShortcutRow(
                        title: "Tags",
                        detail: "Add #tags anywhere in the line; they apply to all names in that entry.",
                        example: "#work #nyc"
                    )
                }

                GuideSection(title: "When you met") {
                    ShortcutRow(
                        title: "Specific date",
                        detail: "Include a date (e.g. Oct 12, 2024 or yesterday). The first date found applies to all names.",
                        example: "Oct 12, 2024 or yesterday"
                    )
                    ShortcutRow(
                        title: "Long time ago",
                        detail: "Add “long time ago” when you don’t remember when you met; the person is grouped separately.",
                        example: "Sarah :: met at tech conference, long time ago"
                    )
                }

                GuideSection(title: "Saving") {
                    ShortcutRow(
                        title: "Quick save",
                        detail: "Press return to save the current line and create or update contacts.",
                        example: "Press ⏎"
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Quick Input Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuideSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            content
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
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(example)
                .font(.callout.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
