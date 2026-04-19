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
    @State private var activeSheet: DocumentSheet?
    @State private var searchText = ""
    @State private var selectedFilter: DocumentFilter = .all

    enum DocumentFilter: String, CaseIterable, Identifiable {
        case all
        case flagged
        case labs
        case visits

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All"
            case .flagged: "Flagged"
            case .labs: "Labs"
            case .visits: "Visits"
            }
        }

        func matches(_ document: MedicalDocument) -> Bool {
            switch self {
            case .all:
                return true
            case .flagged:
                return document.flagged
            case .labs:
                return document.kind == .labPanel
            case .visits:
                return document.kind == .visitNote
            }
        }
    }

    enum DocumentSheet: Identifiable {
        case preview(UIImage)
        case viewer(MedicalDocument)
        var id: String {
            switch self {
            case .preview:        return "preview"
            case .viewer(let d):  return "viewer-\(d.persistentModelID)"
            }
        }
    }

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

    private var visibleDocuments: [MedicalDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return documents.filter { document in
            selectedFilter.matches(document) && (query.isEmpty || matchesSearch(document, query: query))
        }
    }

    private var flaggedDocuments: [MedicalDocument] {
        visibleDocuments.filter(\.flagged)
    }

    private var datedSections: [(title: String, documents: [MedicalDocument])] {
        var sections: [(title: String, documents: [MedicalDocument])] = []

        for document in visibleDocuments where !document.flagged {
            let title = monthSectionTitle(for: document.capturedAt)

            if let existingIndex = sections.firstIndex(where: { $0.title == title }) {
                sections[existingIndex].documents.append(document)
            } else {
                sections.append((title: title, documents: [document]))
            }
        }

        return sections
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                SectionHeader(
                    eyebrow: "Your records",
                    title: "Documents",
                    subtitle: "Every lab, prescription, and visit note — in one place."
                )

                libraryToolsCard
                scanCard

                if visibleDocuments.isEmpty {
                    emptySearchState
                } else {
                    if !flaggedDocuments.isEmpty {
                        recordsSection(
                            title: "Needs attention",
                            subtitle: "\(flaggedDocuments.count) flagged record" + (flaggedDocuments.count == 1 ? "" : "s"),
                            items: flaggedDocuments
                        )
                    }

                    ForEach(datedSections, id: \.title) { section in
                        recordsSection(
                            title: section.title,
                            subtitle: "\(section.documents.count) document" + (section.documents.count == 1 ? "" : "s"),
                            items: section.documents
                        )
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
            .animation(.smooth, value: documents.count)
            .animation(.smooth, value: searchText)
            .animation(.smooth, value: selectedFilter)
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
                    if let img = images.first { activeSheet = .preview(img) }
                },
                onCancel: {
                    showScanner = false
                    stage = .idle
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .preview(let img):
                ScannedDocumentPreviewView(
                    image: img,
                    onUpload: { redacted in
                        activeSheet = nil
                        runPipeline(on: redacted)
                    },
                    onCancel: {
                        activeSheet = nil
                        stage = .idle
                    }
                )
            case .viewer(let doc):
                DocumentImageViewer(document: doc)
            }
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
                    activeSheet = .preview(image)
                } else {
                    stage = .error("Couldn't read that image.")
                }
                pickedItem = nil
            }
        }
    }

    // MARK: Scan entry card

    private var libraryToolsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.coralDeep)

                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("Search title, doctor, lab, or summary")
                        .foregroundStyle(Theme.Palette.inkMuted)
                )
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        Haptics.select()
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Palette.surfaceContainerLowest)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DocumentFilter.allCases) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.horizontal, 1)
            }

            Text(librarySummaryLine)
                .font(Theme.Font.body(12, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLow)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.ambient.opacity(0.26), radius: 10, y: 5)
    }

    private func filterChip(_ filter: DocumentFilter) -> some View {
        let selected = selectedFilter == filter

        return Button {
            Haptics.select()
            withAnimation(.smooth(duration: 0.2)) {
                selectedFilter = filter
            }
        } label: {
            Text(filter.label)
                .font(Theme.Font.body(12, weight: .semibold))
                .foregroundStyle(selected ? Theme.Palette.onPrimary : Theme.Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selected ? Theme.Palette.primary : Theme.Palette.surfaceContainerLowest)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(selected ? Theme.Palette.primary : Theme.Palette.outlineVariant, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var librarySummaryLine: String {
        if visibleDocuments.isEmpty {
            return "No matching records right now."
        }

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedFilter == .all {
            return "\(documents.count) records across labs, prescriptions, and visit notes."
        }

        return "\(visibleDocuments.count) matching record" + (visibleDocuments.count == 1 ? "" : "s") + " shown."
    }

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

    private func runPipeline(on image: UIImage) {
        Task {
            do {
                stage = .reading
                let text = try await TextRecognizer.recognize([image])

                stage = .thinking
                let extracted = try await analyzer.analyze(ocrText: text)

                stage = .saving
                let imageData = image.jpegData(compressionQuality: 0.82)
                let doc = analyzer.persist(extracted, imageData: imageData, into: context)

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

    private func recordsSection(title: String, subtitle: String, items: [MedicalDocument]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.Font.body(18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)

                Spacer()

                Text(subtitle.uppercased())
                    .font(Theme.Font.body(10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.Palette.inkMuted)
            }

            ForEach(items, id: \.persistentModelID) { doc in
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
    }

    private var emptySearchState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No records found")
                .font(Theme.Font.display(24, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)

            Text("Try a different search, switch filters, or scan a new record.")
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.surfaceContainerLow)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Palette.outlineVariant, lineWidth: 1)
        )
    }

    private func documentCard(_ doc: MedicalDocument) -> some View {
        Button {
            Haptics.tap()
            activeSheet = .viewer(doc)
        } label: {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                documentLeadingVisual(doc)
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
                VStack(alignment: .trailing, spacing: 4) {
                    Text(doc.capturedAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkMuted)
                    if doc.imageData != nil {
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.coralDeep)
                    }
                }
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
        } // end Button label
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func documentLeadingVisual(_ doc: MedicalDocument) -> some View {
        if let data = doc.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.Palette.outlineVariant.opacity(0.9), lineWidth: 1)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(doc.flagged ? Theme.Palette.peachTint : Theme.Palette.paperSoft)
                    .frame(width: 42, height: 42)
                Image(systemName: doc.kind.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(doc.flagged ? Theme.Palette.coralDeep : Theme.Palette.ink)
            }
        }
    }

    private func matchesSearch(_ document: MedicalDocument, query: String) -> Bool {
        let resultText = document.results
            .map { "\($0.metric) \($0.valueText) \($0.status.displayName)" }
            .joined(separator: " ")

        let haystack = [
            document.title,
            document.provider ?? "",
            document.summary,
            document.kind.displayName,
            resultText
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(query)
    }

    private func monthSectionTitle(for date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
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
