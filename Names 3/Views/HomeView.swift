import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var tabSelection: AppTab
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Contact> { $0.isArchived == false }, sort: \Contact.timestamp, order: .reverse)
    private var contacts: [Contact]
    @Query private var tags: [Tag]

    @State private var showBulkAddFaces = false
    @State private var showQuizView = false
    @State private var showDeletedView = false
    @State private var showManageTags = false
    @State private var showGroupPhotos = false

    private var todayCount: Int {
        let cal = Calendar.current
        return contacts.filter { !$0.isMetLongAgo && cal.isDateInToday($0.timestamp) }.count
    }

    private var longAgoCount: Int {
        contacts.filter { $0.isMetLongAgo }.count
    }

    private var totalContacts: Int {
        contacts.count
    }

    private var topRecent: [Contact] {
        Array(contacts.prefix(12))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    statsRow

                    quickActions

                    recentSection
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showQuizView) {
            QuizView(contacts: contacts)
        }
        .sheet(isPresented: $showDeletedView) {
            DeletedView()
        }
        .sheet(isPresented: $showManageTags) {
            TagPickerView(mode: .manage)
        }
        .sheet(isPresented: $showBulkAddFaces) {
            BulkAddFacesView(contactsContext: modelContext)
                .modelContainer(BatchModelContainer.shared)
        }
        .sheet(isPresented: $showGroupPhotos) {
            GroupPhotosListView(contactsContext: modelContext)
                .modelContainer(BatchModelContainer.shared)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome back")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Names")
                .font(.largeTitle.bold())
        }
    }

    private var statsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatCard(title: "Total", value: totalContacts, color: .accentColor)
                StatCard(title: "Today", value: todayCount, color: .green)
                StatCard(title: "Long ago", value: longAgoCount, color: .orange)
                StatCard(title: "Tags", value: tags.count, color: .purple)
            }
            .padding(.vertical, 4)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.title3.bold())
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                QuickActionButton(title: "Add Faces", systemImage: "camera.viewfinder", tint: .blue) {
                    showBulkAddFaces = true
                }
                QuickActionButton(title: "Faces Quiz", systemImage: "questionmark.circle", tint: .teal) {
                    showQuizView = true
                }
                QuickActionButton(title: "People", systemImage: "person.3", tint: .indigo) {
                    tabSelection = .people
                }
                QuickActionButton(title: "Explore", systemImage: "camera.macro", tint: .pink) {
                    tabSelection = .explore
                }
                QuickActionButton(title: "Group Photos", systemImage: "person.3.sequence", tint: .mint) {
                    showGroupPhotos = true
                }
                QuickActionButton(title: "Manage Tags", systemImage: "tag", tint: .purple) {
                    showManageTags = true
                }
                QuickActionButton(title: "Deleted", systemImage: "trash", tint: .red) {
                    showDeletedView = true
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent")
                    .font(.title3.bold())
                Spacer()
                Button {
                    tabSelection = .people
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(topRecent) { contact in
                    NavigationLink {
                        ContactDetailsView(contact: contact)
                    } label: {
                        RecentTile(contact: contact)
                            .frame(height: 110)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.title2.bold())
            }
            Spacer()
        }
        .padding()
        .frame(width: 150, height: 70)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.15))
        )
    }
}

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.white)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                    .font(.subheadline.bold())
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct RecentTile: View {
    let contact: Contact

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Image(uiImage: UIImage(data: contact.photo) ?? UIImage())
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))

                if !contact.photo.isEmpty {
                    LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                }

                VStack {
                    Spacer()
                    Text(contact.name ?? "")
                        .font(.footnote.bold())
                        .foregroundStyle(contact.photo.isEmpty ? Color.primary.opacity(0.8) : Color.white.opacity(0.9))
                        .padding(.bottom, 6)
                        .padding(.horizontal, 6)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
    }
}