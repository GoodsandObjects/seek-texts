//
//  LibraryScreen_New.swift
//  Seek
//
//  Library home screen with global search.
//  Loads traditions asynchronously from remote with cache fallback.
//

import SwiftUI

// MARK: - Library Screen New

struct LibraryScreenNew: View {
    @StateObject private var libraryData = LibraryData.shared
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Search Bar
                    searchBar
                        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    // Content based on state
                    switch libraryData.loadState {
                    case .idle, .loading:
                        if libraryData.traditions.isEmpty {
                            loadingView
                        } else {
                            mainContentView
                        }
                    case .loaded:
                        mainContentView
                    case .error(let message):
                        if libraryData.traditions.isEmpty {
                            errorView(message: message)
                        } else {
                            mainContentView
                        }
                    case .offline:
                        if libraryData.traditions.isEmpty {
                            offlineView
                        } else {
                            mainContentView
                        }
                    }
                }
            }
            .themedScreenBackground()
            .navigationTitle("Seek")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(SeekTheme.creamBackground, for: .navigationBar)
            .navigationDestination(for: SearchNavigation.self) { nav in
                switch nav {
                case .reader(let chapterRef):
                    ReaderScreen(chapterRef: chapterRef)
                case .chapters(let bookId, let scriptureId):
                    if let (book, sacredText, tradition) = findBookContext(bookId: bookId, scriptureId: scriptureId) {
                        ChaptersScreen(book: book, sacredText: sacredText, tradition: tradition)
                    }
                }
            }
            .navigationDestination(for: Tradition.ID.self) { traditionId in
                if let tradition = libraryData.traditions.first(where: { $0.id == traditionId }) {
                    TextsScreen(tradition: tradition)
                }
            }
            .task {
                await libraryData.bootstrapIfNeeded()
            }
            .refreshable {
                await libraryData.refresh()
            }
        }
    }

    // MARK: - Main Content View

    @ViewBuilder
    private var mainContentView: some View {
        if isSearching && !searchText.isEmpty {
            searchResultsView
        } else {
            traditionsListView
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            // Skeleton loading placeholders
            ForEach(0..<6, id: \.self) { _ in
                SkeletonRowView()
            }
        }
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
        .padding(.bottom, 24)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
            }

            Text("Unable to load library")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SeekTheme.textPrimary)

            Text("Please check your internet connection and try again.")
                .font(.system(size: 14))
                .foregroundColor(SeekTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await libraryData.retry() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(SeekTheme.maroonAccent)
                .cornerRadius(10)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
    }

    // MARK: - Offline View

    private var offlineView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(SeekTheme.maroonAccent.opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "wifi.slash")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(SeekTheme.maroonAccent)
            }

            Text("You're offline")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SeekTheme.textPrimary)

            Text("Connect to the internet to load texts.")
                .font(.system(size: 14))
                .foregroundColor(SeekTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await libraryData.retry() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(SeekTheme.maroonAccent)
                .cornerRadius(10)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(SeekTheme.textSecondary)

                TextField("Search books... (e.g., Genesis 4)", text: $searchText)
                    .font(.system(size: 16))
                    .foregroundColor(SeekTheme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        performSearch()
                    }
                    .onChange(of: searchText) { _, newValue in
                        if newValue.isEmpty {
                            searchResults = []
                            isSearching = false
                        } else {
                            isSearching = true
                            performSearch()
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(SeekTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(SeekTheme.cardBackground)
            .cornerRadius(14)
            .shadow(color: SeekTheme.cardShadow, radius: 6, x: 0, y: 2)
        }
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        LazyVStack(spacing: SeekTheme.cardSpacing) {
            if searchResults.isEmpty && !searchText.isEmpty {
                // No results
                VStack(spacing: 12) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.5))

                    Text("No books found")
                        .font(.system(size: 15))
                        .foregroundColor(SeekTheme.textSecondary)

                    Text("Try \"Genesis\", \"Al-Faatiha\", or \"Psalms 23\"")
                        .font(.system(size: 13))
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(searchResults) { result in
                    SearchResultRow(result: result) {
                        navigateToResult(result)
                    }
                }
            }
        }
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
        .padding(.bottom, 24)
    }

    // MARK: - Traditions List View

    private var traditionsListView: some View {
        LazyVStack(spacing: SeekTheme.cardSpacing) {
            ForEach(libraryData.traditions) { tradition in
                NavigationLink(value: tradition.id) {
                    LibraryTraditionRowView(tradition: tradition)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, SeekTheme.screenHorizontalPadding)
        .padding(.bottom, 24)
    }

    // MARK: - Actions

    private func performSearch() {
        searchResults = SearchManager.shared.search(searchText, maxResults: 6)
    }

    private func navigateToResult(_ result: SearchResult) {
        if let chapter = result.matchedChapter {
            // Navigate directly to chapter
            let chapterRef = ChapterRef(
                scriptureId: result.scriptureId,
                bookId: result.bookId,
                chapterNumber: chapter,
                bookName: result.bookName
            )
            navigationPath.append(SearchNavigation.reader(chapterRef))
        } else {
            // No chapter specified, go to chapters list
            navigationPath.append(SearchNavigation.chapters(result.bookId, result.scriptureId))
        }
    }

    private func findBookContext(bookId: String, scriptureId: String) -> (Book, SacredText, Tradition)? {
        for tradition in libraryData.traditions {
            for text in tradition.texts where text.id == scriptureId {
                if let book = text.books.first(where: { $0.id == bookId }) {
                    return (book, text, tradition)
                }
            }
        }
        return nil
    }
}

// MARK: - Search Navigation

enum SearchNavigation: Hashable {
    case reader(ChapterRef)
    case chapters(String, String) // bookId, scriptureId
}

// MARK: - Skeleton Row View

private struct SkeletonRowView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(SeekTheme.textSecondary.opacity(0.1))
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 8) {
                // Title placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(SeekTheme.textSecondary.opacity(0.1))
                    .frame(width: 120, height: 16)

                // Subtitle placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(SeekTheme.textSecondary.opacity(0.1))
                    .frame(width: 80, height: 12)
            }

            Spacer()
        }
        .padding(.horizontal, SeekTheme.cardHorizontalPadding)
        .padding(.vertical, SeekTheme.cardVerticalPadding)
        .background(SeekTheme.cardBackground)
        .cornerRadius(SeekTheme.cardCornerRadius)
        .opacity(isAnimating ? 0.6 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: SearchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SeekTheme.maroonAccent.opacity(0.08))
                        .frame(width: 48, height: 48)

                    Image(systemName: result.traditionIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(SeekTheme.maroonAccent)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(result.bookName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(SeekTheme.textPrimary)

                        if let chapter = result.matchedChapter {
                            Text(ScriptureTerminology.chapterBadge(for: result.scriptureId, chapterNumber: chapter))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(SeekTheme.maroonAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(SeekTheme.maroonAccent.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }

                    Text("\(result.scriptureName) • \(result.traditionName)")
                        .font(.system(size: 13))
                        .foregroundColor(SeekTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                ThemedChevron()
            }
            .padding(.horizontal, SeekTheme.cardHorizontalPadding)
            .padding(.vertical, 14)
            .themedCard()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Library Tradition Row View

private struct LibraryTraditionRowView: View {
    let tradition: Tradition

    private var subtitleText: String {
        if tradition.texts.isEmpty {
            return "No texts available"
        } else if tradition.texts.count == 1 {
            return tradition.texts.first!.name
        } else {
            return "\(tradition.texts.count) texts"
        }
    }

    var body: some View {
        SimpleThemedRow(
            icon: tradition.icon,
            title: tradition.name,
            subtitle: subtitleText
        )
    }
}

// MARK: - Preview

#Preview {
    LibraryScreenNew()
}
