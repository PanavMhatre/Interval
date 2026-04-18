import SwiftUI

struct DocumentImageViewer: View {
    let document: MedicalDocument
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var anchor: UnitPoint = .center
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let data = document.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale, anchor: anchor)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { val in
                                        scale = max(1, lastScale * val)
                                    }
                                    .onEnded { val in
                                        lastScale = scale
                                        if scale <= 1 {
                                            withAnimation(.smooth) {
                                                scale = 1
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { val in
                                        guard scale > 1 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + val.translation.width,
                                            height: lastOffset.height + val.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.smooth) {
                                scale = scale > 1 ? 1 : 2
                                lastScale = scale
                                if scale == 1 { offset = .zero; lastOffset = .zero }
                            }
                        }
                } else {
                    ContentUnavailableView(
                        "No image stored",
                        systemImage: "doc.slash",
                        description: Text("This document was saved before image storage was added.")
                    )
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                if let data = document.imageData, let image = UIImage(data: data) {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(document.title, image: Image(uiImage: image))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }
}
