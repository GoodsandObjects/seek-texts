import SwiftUI

// MARK: - Texts Screen

struct TextsScreen: View {
    let tradition: Tradition

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SeekTheme.cardSpacing) {
                ForEach(tradition.texts) { text in
                    NavigationLink(destination: BooksScreen(sacredText: text, tradition: tradition)) {
                        TextRowView(text: text)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, SeekTheme.screenHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .themedScreenBackground()
        .navigationTitle(tradition.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(SeekTheme.creamBackground, for: .navigationBar)
    }
}

// MARK: - Text Row View

private struct TextRowView: View {
    let text: SacredText

    private var subtitleText: String {
        if text.id == "quran" {
            return "114 surahs"
        }
        if text.id == "bhagavad-gita" {
            return "18 chapters"
        }
        if text.description.isEmpty {
            return "\(text.books.count) books"
        } else {
            return text.description
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ThemedIconView(systemName: "book.fill")

            VStack(alignment: .leading, spacing: 4) {
                Text(text.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(SeekTheme.textPrimary)

                Text(subtitleText)
                    .font(.system(size: 13))
                    .foregroundColor(SeekTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            ThemedChevron()
        }
        .padding(.horizontal, SeekTheme.cardHorizontalPadding)
        .padding(.vertical, SeekTheme.cardVerticalPadding)
        .themedCard()
    }
}

// MARK: - Books Screen

struct BooksScreen: View {
    let sacredText: SacredText
    let tradition: Tradition

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SeekTheme.cardSpacing) {
                ForEach(sacredText.books) { book in
                    NavigationLink(destination: destinationView(for: book)) {
                        BookRowView(book: book, scriptureId: sacredText.id)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, SeekTheme.screenHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .themedScreenBackground()
        .navigationTitle(sacredText.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(SeekTheme.creamBackground, for: .navigationBar)
    }

    @ViewBuilder
    private func destinationView(for book: Book) -> some View {
        if shouldOpenReaderDirectly(for: book) {
            ReaderScreen(
                chapterRef: ChapterRef(
                    scriptureId: sacredText.id,
                    bookId: book.id,
                    chapterNumber: directChapterNumber(for: book),
                    bookName: book.name
                ),
                book: book,
                sacredText: sacredText,
                tradition: tradition
            )
        } else {
            ChaptersScreen(book: book, sacredText: sacredText, tradition: tradition)
        }
    }

    private func shouldOpenReaderDirectly(for book: Book) -> Bool {
        if sacredText.id == "quran" {
            return true
        }
        if sacredText.id == "bhagavad-gita" {
            return true
        }
        return false
    }

    private func directChapterNumber(for book: Book) -> Int {
        if sacredText.id == "quran",
           let index = sacredText.books.firstIndex(where: { $0.id == book.id }) {
            return index + 1
        }

        if sacredText.id == "bhagavad-gita",
           let chapterNumber = Int(book.id.replacingOccurrences(of: "chapter-", with: "")) {
            return chapterNumber
        }

        return 1
    }
}

// MARK: - Book Row View

private struct BookRowView: View {
    let book: Book
    let scriptureId: String

    private var normalizedGitaChapterNumber: Int? {
        guard scriptureId == "bhagavad-gita" else { return nil }
        return Int(book.id.replacingOccurrences(of: "chapter-", with: ""))
    }

    private var displayTitle: String {
        if let chapterNumber = normalizedGitaChapterNumber {
            return "Chapter \(chapterNumber)"
        }
        return book.name
    }

    private var subtitleText: String? {
        if scriptureId == "quran" {
            return "Open surah"
        }
        if normalizedGitaChapterNumber != nil {
            return nil
        }
        if book.chapterCount == 1 {
            return "1 chapter"
        } else {
            return "\(book.chapterCount) chapters"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ThemedIconView(systemName: "text.book.closed.fill")

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(SeekTheme.textPrimary)

                if let subtitleText {
                    Text(subtitleText)
                        .font(.system(size: 13))
                        .foregroundColor(SeekTheme.textSecondary)
                }
            }

            Spacer()

            ThemedChevron()
        }
        .padding(.horizontal, SeekTheme.cardHorizontalPadding)
        .padding(.vertical, SeekTheme.cardVerticalPadding)
        .themedCard()
    }
}

// MARK: - Chapters Screen

struct ChaptersScreen: View {
    let book: Book
    let sacredText: SacredText
    let tradition: Tradition

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SeekTheme.cardSpacing) {
                ForEach(1...max(1, book.chapterCount), id: \.self) { chapterNumber in
                    NavigationLink(destination: ReaderScreen(
                        chapterRef: ChapterRef(
                            scriptureId: sacredText.id,
                            bookId: book.id,
                            chapterNumber: chapterNumber,
                            bookName: book.name
                        ),
                        book: book,
                        sacredText: sacredText,
                        tradition: tradition
                    )) {
                        ChapterRowView(chapterNumber: chapterNumber, scriptureId: sacredText.id)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, SeekTheme.screenHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .themedScreenBackground()
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(SeekTheme.creamBackground, for: .navigationBar)
    }
}

// MARK: - Chapter Row View

private struct ChapterRowView: View {
    let chapterNumber: Int
    let scriptureId: String

    private var chapterLabel: String {
        ScriptureTerminology.chapterLabel(for: scriptureId)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(SeekTheme.maroonAccent.opacity(0.08))
                    .frame(width: 44, height: 44)

                Text("\(chapterNumber)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(SeekTheme.maroonAccent)
            }

            Text("\(chapterLabel) \(chapterNumber)")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(SeekTheme.textPrimary)

            Spacer()

            ThemedChevron()
        }
        .padding(.horizontal, SeekTheme.cardHorizontalPadding)
        .padding(.vertical, 12)
        .themedCard()
    }
}
