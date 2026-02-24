//
//  ContactTile.swift
//  Names 3
//
//  Grid tile for a persisted contact. Supports navigation, drag, context menu.
//

import SwiftUI
import SwiftData
import SmoothGradient
import TipKit
import UIKit

struct ContactTile: View {
    let contact: Contact
    @Environment(\.modelContext) private var modelContext
    var onChangeDate: (() -> Void)?
    var showNavigationTip: Bool = false

    var body: some View {
        NavigationLink(value: contact.uuid) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    if !contact.photo.isEmpty, let uiImage = UIImage(data: contact.photo) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(1.22)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))

                        LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.0), .black.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                    } else {
                        ZStack {
                            RadialGradient(
                                colors: [
                                    Color(uiColor: .secondarySystemBackground),
                                    Color(uiColor: .tertiarySystemBackground)
                                ],
                                center: .center,
                                startRadius: 5,
                                endRadius: size.width * 0.7
                            )

                            Color.clear
                                .frame(width: size.width, height: size.height)
                                .liquidGlass(in: RoundedRectangle(cornerRadius: 10), stroke: true)
                        }
                    }

                    VStack {
                        Spacer()
                        Text(contact.name ?? "")
                            .font(.footnote)
                            .bold()
                            .foregroundColor(contact.photo.isEmpty ? Color(uiColor: .label).opacity(0.8) : Color(uiColor: .white).opacity(0.8))
                            .padding(.bottom, 6)
                            .padding(.horizontal, 6)
                            .multilineTextAlignment(.center)
                            .lineSpacing(-2)
                    }
                }
            }
            .aspectRatio(1.0, contentMode: .fit)
            .contentShape(.rect)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.3)
                    .scaleEffect(phase.isIdentity ? 1 : 0.9)
            }
        }
        .popoverTip(ContactNavigationTip(), arrowEdge: .top)
        .draggable(ContactDragRecord(uuid: contact.uuid)) {
            Text(contact.name ?? "Contact")
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu {
            Button {
                onChangeDate?()
            } label: {
                Label("Change Date", systemImage: "calendar")
            }

            Button(role: .destructive) {
                contact.isArchived = true
                contact.archivedDate = Date()
                do {
                    try modelContext.save()
                } catch {
                    print("Save failed: \(error)")
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
