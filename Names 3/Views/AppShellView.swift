import SwiftUI
import SwiftData

enum SidebarItem: String, CaseIterable, Identifiable {
    case people
    case quiz
    case deleted

    var id: Self { self }

    var title: String {
        switch self {
        case .people: return "People"
        case .quiz: return "Faces Quiz"
        case .deleted: return "Deleted"
        }
    }

    var symbol: String {
        switch self {
        case .people: return "person.3"
        case .quiz: return "questionmark.circle"
        case .deleted: return "trash"
        }
    }
}

struct AppShellView: View {
    @State private var selection: SidebarItem? = .people

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.symbol)
                }
            }
            .navigationTitle("Names")
        } detail: {
            switch selection {
            case .people, .none:
                ContentView()
            case .quiz:
                QuizHost()
            case .deleted:
                DeletedView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct QuizHost: View {
    @Query(filter: #Predicate<Contact> { $0.isArchived == false })
    private var contacts: [Contact]

    var body: some View {
        QuizView(contacts: contacts)
    }
}