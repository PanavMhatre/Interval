import SwiftUI

// MARK: - Preview + redaction sheet

struct ScannedDocumentPreviewView: View {
    let image: UIImage
    let onUpload: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var redactions: [RedactionRect] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                hintBanner

                PageRedactionView(image: image, redactions: $redactions)

                bottomBar
            }
            .background(Color.black)
            .navigationTitle("Review Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !redactions.isEmpty {
                        Button("Undo") { redactions.removeLast() }
                            .foregroundStyle(Theme.Palette.coral)
                    }
                }
            }
        }
    }

    private var hintBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("Drag to redact  ·  Tap a box to erase it")
                .font(Theme.Font.body(13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .fill(Theme.Palette.paperSoft)
                    )
            }
            .buttonStyle(.plain)

            Button {
                Haptics.success()
                onUpload(image.applyingRedactions(redactions.map(\.rect)))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.doc.fill")
                    Text("Upload")
                }
                .font(Theme.Font.body(15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Palette.coral)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.paper)
    }
}

// MARK: - Redaction model

struct RedactionRect: Identifiable {
    let id = UUID()
    let rect: CGRect  // image pixel coordinates
}

// MARK: - Canvas-based redaction view

private struct PageRedactionView: View {
    let image: UIImage
    @Binding var redactions: [RedactionRect]

    @State private var dragRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let info = layoutInfo(in: proxy.size)

            Canvas { ctx, _ in
                // Draw image respecting aspect-fit within the canvas
                let imgRect = CGRect(
                    x: info.offsetX, y: info.offsetY,
                    width: info.displaySize.width, height: info.displaySize.height
                )
                ctx.draw(Image(uiImage: image), in: imgRect)

                // Burn in confirmed redaction boxes
                for r in redactions {
                    ctx.fill(Path(toDisplay(r.rect, info: info)), with: .color(.black))
                }

                // Live drag-in-progress box
                if let r = dragRect {
                    ctx.fill(Path(r), with: .color(.black.opacity(0.7)))
                }
            }
            .background(Color.black)
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Draw gesture — creates new redactions
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { val in
                        let s = val.startLocation
                        let c = val.location
                        dragRect = CGRect(
                            x: min(s.x, c.x), y: min(s.y, c.y),
                            width: abs(c.x - s.x), height: abs(c.y - s.y)
                        )
                    }
                    .onEnded { _ in
                        if let r = dragRect, r.width > 8, r.height > 8 {
                            redactions.append(RedactionRect(rect: toImage(r, info: info)))
                        }
                        dragRect = nil
                    }
            )
            // Tap gesture — erases the tapped redaction box
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { val in
                        let pt = val.location
                        if let idx = redactions.firstIndex(where: {
                            toDisplay($0.rect, info: info).contains(pt)
                        }) {
                            redactions.remove(at: idx)
                        }
                    }
            )
        }
    }

    // MARK: Layout helpers

    private struct LayoutInfo {
        let displaySize: CGSize
        let offsetX: CGFloat
        let offsetY: CGFloat
    }

    private func layoutInfo(in containerSize: CGSize) -> LayoutInfo {
        let imgAspect = image.size.width / image.size.height
        let boxAspect = containerSize.width / containerSize.height
        let displaySize: CGSize
        if imgAspect > boxAspect {
            displaySize = CGSize(width: containerSize.width, height: containerSize.width / imgAspect)
        } else {
            displaySize = CGSize(width: containerSize.height * imgAspect, height: containerSize.height)
        }
        return LayoutInfo(
            displaySize: displaySize,
            offsetX: (containerSize.width - displaySize.width) / 2,
            offsetY: (containerSize.height - displaySize.height) / 2
        )
    }

    private func toDisplay(_ rect: CGRect, info: LayoutInfo) -> CGRect {
        let sx = info.displaySize.width / image.size.width
        let sy = info.displaySize.height / image.size.height
        return CGRect(
            x: rect.minX * sx + info.offsetX,
            y: rect.minY * sy + info.offsetY,
            width: rect.width * sx,
            height: rect.height * sy
        )
    }

    private func toImage(_ rect: CGRect, info: LayoutInfo) -> CGRect {
        let sx = image.size.width / info.displaySize.width
        let sy = image.size.height / info.displaySize.height
        return CGRect(
            x: (rect.minX - info.offsetX) * sx,
            y: (rect.minY - info.offsetY) * sy,
            width: rect.width * sx,
            height: rect.height * sy
        )
    }
}

// MARK: - UIImage redaction rendering

extension UIImage {
    func applyingRedactions(_ rects: [CGRect]) -> UIImage {
        guard !rects.isEmpty else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            draw(at: .zero)
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            for rect in rects { ctx.cgContext.fill(rect) }
        }
    }
}
