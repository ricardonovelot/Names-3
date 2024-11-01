//
//  CropView.swift
//  Names 3
//
//  Created by Ricardo on 29/10/24.
//

import SwiftUI

@available(iOS 16.0, *)
struct CropView: View {
    var image: UIImage?
    var onCrop: (UIImage?, CGFloat, CGSize) -> ()
    var initialScale: CGFloat
    var initialOffset: CGSize

    @Environment(\.dismiss) var dismiss

    // MARK: Image Operation Related
    @State private var scale: CGFloat
    @State private var lastScale: CGFloat
    @State private var offset: CGSize
    @State private var lastOffset: CGSize
    @GestureState private var isInteracting: Bool

    init(image: UIImage?, initialScale: CGFloat, initialOffset: CGSize, onCrop: @escaping (UIImage?, CGFloat, CGSize) -> ()) {
        self.image = image
        self.onCrop = onCrop
        self.initialScale = initialScale
        self.initialOffset = initialOffset
        self._scale = State(initialValue: initialScale)
        self._lastScale = State(initialValue: initialScale - 1)
        self._offset = State(initialValue: initialOffset)
        self._lastOffset = State(initialValue: initialOffset)
        self._isInteracting = GestureState(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            imageView()
                .navigationTitle("Crop Image")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Color.black
                        .ignoresSafeArea()
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            let renderer = ImageRenderer(content: imageView(true))
                            renderer.proposedSize = .init(CGSize(width: 300, height: 300))
                            if let uiimage = renderer.uiImage {
                                onCrop(uiimage, scale, offset)
                            } else {
                                onCrop(nil, scale, offset)
                            }
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    func imageView(_ hideGrids: Bool = false) -> some View {
        let cropSize = CGSize(width: 300, height: 300)
        GeometryReader { geometry in
            let size = geometry.size

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(content: {
                        GeometryReader { proxy in
                            let rect = proxy.frame(in: .named("CROPVIEW"))

                            Color.clear
                                .onChange(of: isInteracting) { newValue in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        if rect.minX > 0 {
                                            offset.width -= rect.minX
                                            haptic(.medium)
                                        }
                                        if rect.minY > 0 {
                                            offset.height -= rect.minY
                                            haptic(.medium)
                                        }
                                        if rect.maxX < size.width {
                                            offset.width = rect.minX - offset.width
                                            haptic(.medium)
                                        }
                                        if rect.maxY < size.height {
                                            offset.height = rect.minY - offset.height
                                            haptic(.medium)
                                        }
                                    }
                                    if !newValue {
                                        lastOffset = offset
                                    }
                                }
                        }
                    })
                    .frame(width: size.width, height: size.height)
            }
        }
        .scaleEffect(scale)
        .offset(offset)
        .overlay(content: {
            if !hideGrids {
                Grids()
            }
        })
        .coordinateSpace(name: "CROPVIEW")
        .gesture(
            DragGesture()
                .updating($isInteracting, body: { _, state, _ in
                    state = true
                })
                .onChanged({ value in
                    offset = CGSize(width: value.translation.width + lastOffset.width, height: value.translation.height + lastOffset.height)
                })
        )
        .gesture(
            MagnificationGesture()
                .updating($isInteracting, body: { _, state, _ in
                    state = true
                })
                .onChanged({ value in
                    let updatedScale = lastScale + value - 1
                    scale = updatedScale < 1 ? 1 : updatedScale
                })
                .onEnded({ value in
                    lastScale = scale
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if scale < 1 {
                            scale = 1
                            lastScale = 1
                        }
                    }
                })
        )
        .frame(width: cropSize.width, height: cropSize.height)
        .cornerRadius(0)
        .background(
            ZStack {
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: cropSize.width, height: cropSize.height)
                    .border(Color.white, width: 1)
            }
        )
    }

    @ViewBuilder
    func Grids() -> some View {
        ZStack {
            HStack {
                ForEach(1...(300 / 60), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack {
                ForEach(1...(300 / 60), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct CropView_Previews: PreviewProvider {
    static var previews: some View {
        CropView(image: UIImage(named: "sampleImage"), initialScale: 1.0, initialOffset: .zero) { _, _, _ in
        }
    }
}

extension View {
    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
