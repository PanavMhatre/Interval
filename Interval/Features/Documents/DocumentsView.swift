import SwiftUI
import SwiftData
import PhotosUI

struct DocumentsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\MedicalDocument.capturedAt, order: .reverse)])
    private var documents: [MedicalDocument]

    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var stage: PipelineStage = .idle
    @State private var justAddedID: PersistentIdentifier?

    private let analyzer = DocumentAnalyzer()

    enum PipelineStage: Equatable {
        case idle, capturing, reading, thinking, saving
        case error(String)

        var label: String {
            switch self {
            case .idle: ""
            case .capturing: "Capturing…"
            case .reading:   "Reading the page…"
            case .thinking:  "Understanding what this means…"
            case .saving:    "Filing it in your profile…"
            case .error(let msg): msg
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                SectionHeader(
                    eyebrow: "Your records",
                    title: "Documents",
                    subtitle: "Every lab, prescription, and visit note — in one place."
                )

                scanCard

                ForEach(documents, id: \.persistentModelID) { doc in
                    documentCard(doc)
                        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
                        .overlay(
                            justAddedID == doc.persistentModelID ?
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .stroke(Theme.Palette.coral, lineWidth: 2)
                                    .allowsHitTesting(false)
                                : nil
                        )
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
            .animation(.smooth, value: documents.count)
        }
        .background(Theme.Palette.paper)
        .overlay {
            if stage != .idle { pipelineOverlay }
        }
        .animation(.smooth, value: stage)
        .sheet(isPresented: $showScanner) {
            DocumentScanner(
                onComplete: { images in
                    showScanner = false
                    runPipeline(on: images)
                },
                onCancel: {
                    showScanner = false
                    stage = .idle
                }
            )
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickedItem,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .onChange(of: pickedItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    runPipeline(on: [image])
                } else {
                    stage = .error("Couldn't read that image.")
                }
                pickedItem = nil
            }
        }
    }

    // MARK: Scan entry card

    private var scanCard: some View {
        Button {
            Haptics.tap()
            beginCapture()
        } label: {
            HStack(spacing: Theme.Space.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.Palette.peachTint)
                        .frame(width: 54, height: 54)
                    Image(systemName: "doc.viewfinder.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scan new document")
                        .font(Theme.Font.body(16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(scanHint)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Palette.coralDeep)
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Palette.peachSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.Palette.coral.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var scanHint: String {
        DocumentScanner.isSupported
            ? "Lab, prescription, or visit note — I'll parse it."
            : "No camera on this device — pick an image instead."
    }

    private func beginCapture() {
        stage = .capturing
        if DocumentScanner.isSupported {
            showScanner = true
        } else {
            showPhotoPicker = true
        }
    }

    // MARK: Pipeline

    private func runPipeline(on images: [UIImage]) {
        guard !images.isEmpty else { stage = .idle; return }

        Task {
            do {
                stage = .reading
                let text = try await TextRecognizer.recognize(images)

                stage = .thinking
                let extracted = try await analyzer.analyze(ocrText: text)

                stage = .saving
                let doc = analyzer.persist(extracted, into: context)

                Haptics.success()
                withAnimation(.smooth) {
                    justAddedID = doc.persistentModelID
                    stage = .idle
                }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation { justAddedID = nil }
            } catch {
                Haptics.error()
                stage = .error(error.localizedDescription)
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                stage = .idle
            }
        }
    }

    // MARK: Document card

    private func documentCard(_ doc: MedicalDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(doc.flagged ? Theme.Palette.peachTint : Theme.Palette.paperSoft)
                        .frame(width: 38, height: 38)
                    Image(systemName: doc.kind.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(doc.flagged ? Theme.Palette.coralDeep : Theme.Palette.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(doc.title)
                            .font(Theme.Font.body(16, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        if doc.flagged {
                            StatusChip(text: "Flag", kind: .flag)
                        }
                    }
                    Text(doc.provider ?? doc.kind.displayName)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
                Spacer()
                Text(doc.capturedAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }

            if !doc.summary.isEmpty {
                Text(doc.summary)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }

            if !doc.results.isEmpty {
                DashedHairline()
                VStack(spacing: 6) {
                    ForEach(doc.results.prefix(4), id: \.persistentModelID) { result in
                        HStack {
                            Text(result.metric)
                                .font(Theme.Font.body(13, weight: .medium))
                                .foregroundStyle(Theme.Palette.ink)
                            Spacer()
                            Text(result.valueText)
                                .font(Theme.Font.body(13, weight: .semibold))
                                .foregroundStyle(statusColor(result.status))
                            statusBadge(result.status)
                        }
                    }
                }
            }
        }
        .padding(Theme.Space.md)
        .softCard()
    }

    @ViewBuilder
    private func statusBadge(_ status: LabStatus) -> some View {
        switch status {
        case .normal: StatusChip(text: "OK", kind: .done)
        case .low:    StatusChip(text: "↓ Low", kind: .flag)
        case .high:   StatusChip(text: "↑ High", kind: .flag)
        }
    }

    private func statusColor(_ status: LabStatus) -> Color {
        switch status {
        case .normal: Theme.Palette.ink
        case .low, .high: Theme.Palette.coralDeep
        }
    }

    // MARK: Pipeline overlay

    private var pipelineOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                pipelineArt
                Text(stage.label)
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralDeep)
                    Text("On-device · nothing leaves your phone")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkMuted)
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.xl)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    @ViewBuilder
    private var pipelineArt: some View {
        let steps: [(String, PipelineStage)] = [
            ("doc.viewfinder", .capturing),
            ("text.viewfinder", .reading),
            ("sparkles",       .thinking),
            ("tray.and.arrow.down.fill", .saving)
        ]
        HStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                let active = isActive(step.1)
                ZStack {
                    Circle()
                        .fill(active ? Theme.Palette.coral : Theme.Palette.paperSoft)
                        .frame(width: 38, height: 38)
                    Image(systemName: step.0)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(active ? .white : Theme.Palette.inkMuted)
                }
                .scaleEffect(active ? 1.05 : 1)
                .animation(.smooth(duration: 0.3), value: active)
            }
        }
    }

    private func isActive(_ target: PipelineStage) -> Bool {
        // A step is considered "active" once we've reached or passed it.
        func rank(_ s: PipelineStage) -> Int {
            switch s {
            case .idle: 0
            case .capturing: 1
            case .reading: 2
            case .thinking: 3
            case .saving: 4
            case .error: 0
            }
        }
        return rank(stage) >= rank(target) && rank(stage) > 0
    }
}

#Preview {
    NavigationStack { DocumentsView() }
        .modelContainer(previewContainer())
}
