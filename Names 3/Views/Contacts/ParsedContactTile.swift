//
//  ParsedContactTile.swift
//  Names 3
//
//  Grid tile for a parsed (not yet persisted) contact.
//

import SwiftUI
import SwiftData
import SmoothGradient
import UIKit

struct ParsedContactTile: View {
    let contact: Contact

    var body: some View {
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
                        .background(Color(uiColor: .black).opacity(0.05))
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
                        .foregroundColor(UIImage(data: contact.photo) != UIImage() ? Color(uiColor: .label).opacity(0.8) : Color(uiColor: .white).opacity(0.8))
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
        .draggable(ContactDragRecord(uuid: contact.uuid)) {
            Text(contact.name ?? "Contact")
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
