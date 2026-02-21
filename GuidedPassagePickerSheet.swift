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

    private struct FlatBookOption: Identifiable {
        let traditionId: String
        let traditionName: String
        let scriptureId: String
        let scriptureName: String
        let book: Book

        var id: String {
            "\(scriptureId)-\(book.id)"
        }

        var title: String {
            "\(book.name)"
        }

        var subtitle: String {
            "\(scriptureName)"
        }
    }

    private struct FlatScriptureOption: Identifiable {
        let tradition: Tradition
        let scripture: SacredText

        var id: String {
            "\(tradition.id)-\(scripture.id)"
        }
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

    private var allScriptureOptions: [FlatScriptureOption] {
        libraryData.traditions.flatMap { tradition in
            tradition.texts.map { FlatScriptureOption(tradition: tradition, scripture: $0) }
        }
    }

    private var allBookOptions: [FlatBookOption] {
        let options = allScriptureOptions.flatMap { option in
            option.scripture.books.map { book in
                FlatBookOption(
                    traditionId: option.tradition.id,
                    traditionName: option.tradition.name,
                    scriptureId: option.scripture.id,
                    scriptureName: option.scripture.name,
                    book: book
                )
            }
        }

        return options.sorted {
            if $0.book.name == $1.book.name {
                return $0.scriptureName < $1.scriptureName
            }
            return $0.book.name < $1.book.name
        }
    }

    private var selectedBookOption: FlatBookOption? {
        allBookOptions.first { option in
            option.traditionId == selectedTraditionId &&
            option.scriptureId == selectedScriptureId &&
            option.book.id == selectedBookId
        }
    }

    private var maxUnitNumber: Int {
        max(1, selectedBook?.chapterCount ?? 1)
    }

    private var maxRangeVerse: Int {
        guard let scriptureId = selectedScripture?.id, let bookId = selectedBook?.id else {
            return 176
        }
        let loaded = VerseLoader.shared.load(scriptureId: scriptureId, bookId: bookId, chapter: selectedUnitNumber).count
        return max(1, loaded == 0 ? 176 : loaded)
    }

    private var unitLabel: String {
        guard let scripture = selectedScripture else { return "Chapter" }
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

    private var readEntireLabel: String {
        "Read Entire \(unitLabel)"
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

                    selectionCard
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
            .onChange(of: selectedUnitNumber) { _, _ in
                normalizeRangeBounds()
            }
            .onChange(of: useRange) { _, enabled in
                if enabled {
                    normalizeRangeBounds()
                }
            }
            .onChange(of: searchText) { _, _ in
                scheduleSearch()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionStepLabel("Step 1", title: "Text")
            Menu {
                ForEach(allScriptureOptions) { option in
                    Button {
                        selectedTraditionId = option.tradition.id
                        selectedScriptureId = option.scripture.id
                        if let firstBook = option.scripture.books.first {
                            selectedBookId = firstBook.id
                        }
                        selectedUnitNumber = 1
                        useRange = false
                        rangeStart = 1
                        rangeEnd = 8
                    } label: {
                        Text(option.scripture.name)
                    }
                }
            } label: {
                selectionRow(
                    title: selectedScripture?.name ?? "Select Text",
                    subtitle: selectedTradition?.name ?? "Choose a scripture dataset",
                    isEnabled: !allScriptureOptions.isEmpty
                )
            }
            .disabled(allScriptureOptions.isEmpty)

            sectionStepLabel("Step 2", title: "Book")
            Menu {
                ForEach(allBookOptions) { option in
                    Button {
                        selectedTraditionId = option.traditionId
                        selectedScriptureId = option.scriptureId
                        selectedBookId = option.book.id
                        selectedUnitNumber = 1
                        useRange = false
                        rangeStart = 1
                        rangeEnd = 8
                    } label: {
                        Text("\(option.title) • \(option.subtitle)")
                    }
                }
            } label: {
                selectionRow(
                    title: selectedBookOption?.title ?? "Select Book",
                    subtitle: selectedBookOption?.subtitle ?? "Choose a passage source",
                    isEnabled: !allBookOptions.isEmpty
                )
            }
            .disabled(allBookOptions.isEmpty)

            sectionStepLabel("Step 3", title: unitLabel)
            if maxUnitNumber > 1 {
                Menu {
                    ForEach(1...maxUnitNumber, id: \.self) { unit in
                        Button("\(unit)") { selectedUnitNumber = unit }
                    }
                } label: {
                    selectionRow(
                        title: "\(unitLabel) \(selectedUnitNumber)",
                        subtitle: "Choose the \(unitLabel.lowercased())",
                        isEnabled: canApply
                    )
                }
                .disabled(!canApply)
            } else {
                selectionRow(
                    title: "\(unitLabel) 1",
                    subtitle: "This text has a single \(unitLabel.lowercased())",
                    isEnabled: canApply
                )
            }

            sectionStepLabel("Step 4", title: "Range")
            HStack(spacing: 8) {
                scopeButton(title: readEntireLabel, selected: !useRange) {
                    useRange = false
                }

                scopeButton(title: "\(rangeLabel) Range", selected: useRange) {
                    useRange = true
                }
            }
            .disabled(!canApply)
            .opacity(canApply ? 1.0 : 0.5)

            if useRange && canApply {
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
                        maximum: maxRangeVerse
                    )

                    Text("\(rangeLabel) \(rangeStart)-\(rangeEnd)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SeekTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 2)
            }

            sectionStepLabel("Step 5", title: "Ready")
            Button {
                applySelection()
            } label: {
                Text("Begin Guided Study")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(canApply ? SeekTheme.maroonAccent : SeekTheme.textSecondary.opacity(0.35))
                    .cornerRadius(11)
            }
            .disabled(!canApply)
        }
        .padding(16)
        .background(SeekTheme.cardBackground)
        .cornerRadius(16)
    }

    private func sectionStepLabel(_ step: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(step)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SeekTheme.maroonAccent)
                .textCase(.uppercase)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SeekTheme.textSecondary)
        }
    }

    private func selectionRow(title: String, subtitle: String, isEnabled: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isEnabled ? SeekTheme.textPrimary : SeekTheme.textSecondary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(SeekTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SeekTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SeekTheme.creamBackground)
        .cornerRadius(10)
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
        guard !libraryData.traditions.isEmpty else { return }

        if let initialOption = allBookOptions.first(where: {
            $0.scriptureId == initialSelection.scriptureId &&
            $0.book.id == initialSelection.bookId
        }) {
            selectedTraditionId = initialOption.traditionId
            selectedScriptureId = initialOption.scriptureId
            selectedBookId = initialOption.book.id
        } else if let first = allBookOptions.first {
            selectedTraditionId = first.traditionId
            selectedScriptureId = first.scriptureId
            selectedBookId = first.book.id
        }

        useRange = initialScope == .range
        if let initialRange {
            rangeStart = max(1, initialRange.lowerBound)
            rangeEnd = max(rangeStart, initialRange.upperBound)
        }

        if initialSelection.chapterNumber > 0 {
            selectedUnitNumber = initialSelection.chapterNumber
        }
    }

    private func normalizeSelectionForDependencies(
        changedTradition: Bool = false,
        changedScripture: Bool = false,
        changedBook: Bool = false
    ) {
        if selectedTradition == nil,
           let firstTradition = libraryData.traditions.first {
            selectedTraditionId = firstTradition.id
        }

        guard let tradition = selectedTradition else { return }

        if selectedScripture == nil,
           let firstScripture = tradition.texts.first {
            selectedScriptureId = firstScripture.id
        }

        guard let scripture = selectedScripture else { return }

        if selectedBook == nil,
           let firstBook = scripture.books.first {
            selectedBookId = firstBook.id
        }

        if changedTradition || changedScripture || changedBook {
            let maxChapter = max(1, selectedBook?.chapterCount ?? 1)
            selectedUnitNumber = min(max(1, selectedUnitNumber), maxChapter)
        }

        let preferred = initialSelection.chapterNumber
        let maxChapter = max(1, selectedBook?.chapterCount ?? 1)
        if selectedUnitNumber < 1 || selectedUnitNumber > maxChapter {
            selectedUnitNumber = min(max(1, preferred), maxChapter)
        }

        normalizeRangeBounds()
    }

    private func normalizeRangeBounds() {
        let maxVerse = maxRangeVerse

        if rangeStart < 1 {
            rangeStart = 1
        }

        if rangeStart > maxVerse {
            rangeStart = maxVerse
        }

        if rangeEnd < rangeStart {
            rangeEnd = rangeStart
        }

        if rangeEnd > maxVerse {
            rangeEnd = maxVerse
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

    private func rangeStepper(title: String, value: Binding<Int>, minimum: Int, maximum: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

            Text("Up to \(maxRangeVerse) \(rangeLabelPluralLowercased)")
                .font(.system(size: 11))
                .foregroundColor(SeekTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
