import SwiftUI

struct GuidedPassagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var libraryData = LibraryData.shared

    private let initialSelection: GuidedPassageSelectionRef
    private let initialScope: GuidedSessionScope
    private let initialRange: ClosedRange<Int>?
    private let onApply: (GuidedPassageSelectionRef, GuidedSessionScope, ClosedRange<Int>?) -> Void

    @State private var selectedTraditionId: String = ""
    @State private var selectedScriptureId: String = ""
    @State private var selectedBookId: String = ""
    @State private var selectedUnitNumber: Int = 1
    @State private var useRange = false
    @State private var rangeStart: Int = 1
    @State private var rangeEnd: Int = 8

    @State private var searchText = ""
    @State private var searchResults: [GuidedSearchResult] = []
    @State private var isSearching = false
    @State private var hasInitialized = false
    @State private var searchTask: Task<Void, Never>?

    init(
        initialSelection: GuidedPassageSelectionRef,
        initialScope: GuidedSessionScope,
        initialRange: ClosedRange<Int>?,
        onApply: @escaping (GuidedPassageSelectionRef, GuidedSessionScope, ClosedRange<Int>?) -> Void
    ) {
        self.initialSelection = initialSelection
        self.initialScope = initialScope
        self.initialRange = initialRange
        self.onApply = onApply
    }

    private var selectedTradition: Tradition? {
        libraryData.traditions.first(where: { $0.id == selectedTraditionId })
    }

    private var selectedScripture: SacredText? {
        selectedTradition?.texts.first(where: { $0.id == selectedScriptureId })
    }

    private var selectedBook: Book? {
        selectedScripture?.books.first(where: { $0.id == selectedBookId })
    }

    private var availableTraditions: [Tradition] {
        libraryData.traditions
    }

    private var availableScriptures: [SacredText] {
        selectedTradition?.texts ?? []
    }

    private var availableBooks: [Book] {
        selectedScripture?.books ?? []
    }

    private var maxUnitNumber: Int {
        max(1, selectedBook?.chapterCount ?? 1)
    }

    private var unitLabel: String {
        guard let scripture = selectedScripture else { return "Unit" }
        return ScriptureTerminology.chapterLabel(for: scripture.id)
    }

    private var rangeLabel: String {
        guard let scripture = selectedScripture else { return "Verse" }
        return ScriptureTerminology.verseLabel(for: scripture.id)
    }

    private var rangeLabelPluralLowercased: String {
        guard let scripture = selectedScripture else { return "verses" }
        return ScriptureTerminology.verseLabelLowercased(for: scripture.id, plural: true)
    }

    private var bookLabel: String {
        guard let scripture = selectedScripture else { return "Book" }
        return scripture.id == "quran" ? "Surah" : "Book"
    }

    private var scopePrimaryLabel: String {
        maxUnitNumber <= 1 ? "Full Passage" : "Full \(unitLabel)"
    }

    private var canApply: Bool {
        selectedTradition != nil && selectedScripture != nil && selectedBook != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    searchHeader

                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchResultsSection
                    }

                    advancedControlsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .themedScreenBackground()
            .navigationTitle("Change Passage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(SeekTheme.maroonAccent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") {
                        applySelection()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(canApply ? SeekTheme.maroonAccent : SeekTheme.textSecondary)
                    .disabled(!canApply)
                }
            }
            .task {
                if libraryData.traditions.isEmpty {
                    await libraryData.bootstrapIfNeeded()
                }
                await GuidedSearchManager.shared.warmIndex(with: libraryData.traditions)

                if !hasInitialized {
                    restoreInitialSelectionIfPossible()
                    normalizeSelectionForDependencies()
                    hasInitialized = true
                }
            }
            .onChange(of: selectedTraditionId) { _, _ in
                normalizeSelectionForDependencies(changedTradition: true)
            }
            .onChange(of: selectedScriptureId) { _, _ in
                normalizeSelectionForDependencies(changedScripture: true)
            }
            .onChange(of: selectedBookId) { _, _ in
                normalizeSelectionForDependencies(changedBook: true)
            }
            .onChange(of: useRange) { _, enabled in
                if enabled {
                    rangeStart = max(1, rangeStart)
                    rangeEnd = max(rangeStart, rangeEnd)
                }
            }
            .onChange(of: searchText) { _, _ in
                scheduleSearch()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SeekTheme.textSecondary)

            TextField("Search passage or topic (e.g. Genesis 4, mercy, patience)", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(SeekTheme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if isSearching {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: SeekTheme.maroonAccent))
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(SeekTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(SeekTheme.cardBackground)
        .cornerRadius(14)
        .shadow(color: SeekTheme.cardShadow, radius: 6, x: 0, y: 2)
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !searchResults.isEmpty {
                ForEach(searchResults) { result in
                    Button {
                        applySearchResult(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.reference)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(SeekTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(result.preview)
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(result.religionLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(SeekTheme.maroonAccent)
                                .textCase(.uppercase)
                        }
                        .padding(12)
                        .background(SeekTheme.cardBackground)
                        .cornerRadius(12)
                        .shadow(color: SeekTheme.cardShadow, radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            } else if !isSearching {
                Text("No passages found. Try a book reference or a broader keyword.")
                    .font(.system(size: 13))
                    .foregroundColor(SeekTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(12)
            }
        }
    }

    private var advancedControlsSection: some View {
        VStack(spacing: 14) {
            pickerCard(title: "Religion") {
                menuPicker(
                    selection: $selectedTraditionId,
                    options: availableTraditions.map { ($0.id, $0.name) },
                    placeholder: "Select religion"
                )
            }

            pickerCard(title: "Text") {
                menuPicker(
                    selection: $selectedScriptureId,
                    options: availableScriptures.map { ($0.id, $0.name) },
                    placeholder: "Select text"
                )
            }

            pickerCard(title: bookLabel) {
                menuPicker(
                    selection: $selectedBookId,
                    options: availableBooks.map { ($0.id, displayBookTitle($0)) },
                    placeholder: "Select \(bookLabel.lowercased())"
                )
            }

            if maxUnitNumber > 1 {
                pickerCard(title: unitLabel) {
                    HStack(spacing: 10) {
                        Button {
                            selectedUnitNumber = max(1, selectedUnitNumber - 1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(selectedUnitNumber > 1 ? SeekTheme.maroonAccent : SeekTheme.textSecondary.opacity(0.35))
                                .frame(width: 36, height: 36)
                        }
                        .disabled(selectedUnitNumber <= 1)

                        Text("\(selectedUnitNumber)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(SeekTheme.textPrimary)
                            .frame(maxWidth: .infinity)

                        Button {
                            selectedUnitNumber = min(maxUnitNumber, selectedUnitNumber + 1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(selectedUnitNumber < maxUnitNumber ? SeekTheme.maroonAccent : SeekTheme.textSecondary.opacity(0.35))
                                .frame(width: 36, height: 36)
                        }
                        .disabled(selectedUnitNumber >= maxUnitNumber)
                    }
                }
            }

            pickerCard(title: "Current Passage") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        scopeButton(title: scopePrimaryLabel, selected: !useRange) {
                            useRange = false
                        }

                        scopeButton(title: "Range", selected: useRange) {
                            useRange = true
                        }
                    }

                    if useRange {
                        VStack(spacing: 10) {
                            rangeStepper(
                                title: "From",
                                value: $rangeStart,
                                minimum: 1,
                                maximum: max(1, rangeEnd)
                            )

                            rangeStepper(
                                title: "To",
                                value: $rangeEnd,
                                minimum: max(1, rangeStart),
                                maximum: 176
                            )

                            Text("\(rangeLabel) \(rangeStart)-\(rangeEnd)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(SeekTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func scopeButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selected ? .white : SeekTheme.maroonAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? SeekTheme.maroonAccent : SeekTheme.maroonAccent.opacity(0.08))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func restoreInitialSelectionIfPossible() {
        guard !availableTraditions.isEmpty else { return }

        selectedTraditionId = availableTraditions.contains(where: { $0.id == initialSelection.traditionId })
            ? initialSelection.traditionId
            : availableTraditions[0].id

        useRange = initialScope == .range
        if let initialRange {
            rangeStart = max(1, initialRange.lowerBound)
            rangeEnd = max(rangeStart, initialRange.upperBound)
        }
    }

    private func normalizeSelectionForDependencies(
        changedTradition: Bool = false,
        changedScripture: Bool = false,
        changedBook: Bool = false
    ) {
        if selectedTradition == nil, let first = availableTraditions.first {
            selectedTraditionId = first.id
        }

        let scriptures = availableScriptures
        if scriptures.isEmpty {
            selectedScriptureId = ""
            selectedBookId = ""
            selectedUnitNumber = 1
            return
        }

        if changedTradition || !scriptures.contains(where: { $0.id == selectedScriptureId }) {
            selectedScriptureId = scriptures.contains(where: { $0.id == initialSelection.scriptureId })
                ? initialSelection.scriptureId
                : scriptures[0].id
        }

        let books = availableBooks
        if books.isEmpty {
            selectedBookId = ""
            selectedUnitNumber = 1
            return
        }

        if changedScripture || !books.contains(where: { $0.id == selectedBookId }) {
            selectedBookId = books.contains(where: { $0.id == initialSelection.bookId })
                ? initialSelection.bookId
                : books[0].id
        }

        let maxChapter = maxUnitNumber

        if changedScripture || changedBook || selectedUnitNumber > maxChapter {
            let preferred = initialSelection.chapterNumber
            selectedUnitNumber = min(max(1, preferred), maxChapter)
        }

        if selectedUnitNumber < 1 {
            selectedUnitNumber = 1
        }

        if selectedUnitNumber > maxChapter {
            selectedUnitNumber = maxChapter
        }

        if rangeStart < 1 {
            rangeStart = 1
        }

        if rangeEnd < rangeStart {
            rangeEnd = rangeStart
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            isSearching = false
            searchResults = []
            return
        }

        searchTask = Task {
            isSearching = true
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }

            let results = await GuidedSearchManager.shared.search(
                query: query,
                traditions: libraryData.traditions,
                maxResults: 16
            )

            if Task.isCancelled { return }
            searchResults = results
            isSearching = false
        }
    }

    private func applySearchResult(_ result: GuidedSearchResult) {
        onApply(result.selection, result.scope, result.range)
        dismiss()
    }

    private func applySelection() {
        guard let tradition = selectedTradition,
              let scripture = selectedScripture,
              let book = selectedBook else {
            return
        }

        let selection = GuidedPassageSelectionRef(
            traditionId: tradition.id,
            traditionName: tradition.name,
            scriptureId: scripture.id,
            scriptureName: scripture.name,
            bookId: book.id,
            bookName: book.name,
            chapterNumber: selectedUnitNumber
        )

        let scope: GuidedSessionScope = useRange ? .range : .chapter
        let range: ClosedRange<Int>? = useRange ? (rangeStart...rangeEnd) : nil

        onApply(selection, scope, range)
        dismiss()
    }

    private func pickerCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SeekTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SeekTheme.cardBackground)
        .cornerRadius(14)
        .shadow(color: SeekTheme.cardShadow, radius: 6, x: 0, y: 2)
    }

    private func menuPicker(
        selection: Binding<String>,
        options: [(id: String, title: String)],
        placeholder: String
    ) -> some View {
        Menu {
            ForEach(options, id: \.id) { option in
                Button(option.title) {
                    selection.wrappedValue = option.id
                }
            }
        } label: {
            HStack {
                Text(options.first(where: { $0.id == selection.wrappedValue })?.title ?? placeholder)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(options.isEmpty ? SeekTheme.textSecondary : SeekTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SeekTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(SeekTheme.creamBackground)
            .cornerRadius(10)
        }
    }

    private func displayBookTitle(_ book: Book) -> String {
        guard let scripture = selectedScripture else { return book.name }
        if scripture.id == "quran" {
            let ayahs = VerseLoader.shared.load(scriptureId: scripture.id, bookId: book.id, chapter: 1).count
            if ayahs > 0 {
                return "\(book.name) • \(ayahs) ayahs"
            }
            return book.name
        }
        return book.name
    }

    private func rangeStepper(title: String, value: Binding<Int>, minimum: Int, maximum: Int) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SeekTheme.textSecondary)
                .frame(width: 52, alignment: .leading)

            HStack(spacing: 0) {
                Button {
                    value.wrappedValue = max(minimum, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(value.wrappedValue > minimum ? SeekTheme.maroonAccent : SeekTheme.textSecondary.opacity(0.35))
                        .frame(width: 34, height: 34)
                }
                .disabled(value.wrappedValue <= minimum)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(SeekTheme.textPrimary)
                    .frame(maxWidth: .infinity)

                Button {
                    value.wrappedValue = min(maximum, value.wrappedValue + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(value.wrappedValue < maximum ? SeekTheme.maroonAccent : SeekTheme.textSecondary.opacity(0.35))
                        .frame(width: 34, height: 34)
                }
                .disabled(value.wrappedValue >= maximum)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(SeekTheme.creamBackground)
            .cornerRadius(10)
        }
    }
}
