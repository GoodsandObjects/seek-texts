//
//  ShareImageGenerator.swift
//  Seek
//
//  Generates branded image cards for sharing verses.
//  Uses SwiftUI ImageRenderer for iOS 16+.
//

import SwiftUI

// MARK: - Share Content Types

enum ShareContentType {
    case verse
    case highlight
    case note
    case multiVerse
    case guidedInsight  // Future: for guided study sharing
}

// MARK: - Share Content Model

struct ShareContent {
    let reference: String       // e.g., "Genesis 1:1"
    let verseText: String       // The verse content
    let scriptureName: String   // e.g., "Bible (KJV)"
    let noteText: String?       // Optional note
    let contentType: ShareContentType

    init(reference: String, verseText: String, scriptureName: String, noteText: String? = nil, contentType: ShareContentType = .verse) {
        self.reference = reference
        self.verseText = verseText
        self.scriptureName = scriptureName
        self.noteText = noteText
        self.contentType = contentType
    }
}

// MARK: - Share Card View (Standard Verse + Note)

struct ShareCardView: View {
    let content: ShareContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top accent bar
            Rectangle()
                .fill(Color(red: 0.75, green: 0.38, blue: 0.28))
                .frame(height: 6)

            VStack(alignment: .leading, spacing: 20) {
                // Reference header
                VStack(alignment: .leading, spacing: 6) {
                    Text(content.reference)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.28))

                    Text(content.scriptureName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.55, green: 0.50, blue: 0.45))
                }

                // Verse text
                Text(content.verseText)
                    .font(.custom("Georgia", size: 18))
                    .foregroundColor(Color(red: 0.12, green: 0.10, blue: 0.08))
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)

                // Optional note
                if let note = content.noteText, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "note.text")
                                .font(.system(size: 12, weight: .medium))
                            Text("Note")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.28))

                        Text(note)
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.35, green: 0.32, blue: 0.28))
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1.0, green: 0.96, blue: 0.90))
                    .cornerRadius(12)
                }

                Spacer(minLength: 16)

                // Footer with Seek branding
                HStack {
                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                        Text("Shared via Seek")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.28).opacity(0.6))
                }
            }
            .padding(28)
        }
        .frame(width: 380)
        .background(Color(red: 0.97, green: 0.95, blue: 0.92))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Highlight Share Card View

struct HighlightShareCardView: View {
    let content: ShareContent
    private let highlightYellow = Color(red: 1.0, green: 0.95, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top accent bar
            Rectangle()
                .fill(Color(red: 0.75, green: 0.38, blue: 0.28))
                .frame(height: 6)

            VStack(alignment: .leading, spacing: 20) {
                // Reference header with highlight indicator
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(content.reference)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.28))

                        Text(content.scriptureName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 0.55, green: 0.50, blue: 0.45))
                    }

                    Spacer()

                    Image(systemName: "highlighter")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.28).opacity(0.5))
                }

                // Verse text with highlight styling
                Text(content.verseText)
                    .font(.custom("Georgia", size: 18))
                    .foregroundColor(Color(red: 0.12, green: 0.10, blue: 0.08))
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(highlightYellow)
                    .cornerRadius(12)

                Spacer(minLength: 16)

                // Footer with Seek branding
                HStack {
                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                        Text("Shared via Seek")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.28).opacity(0.6))
                }
            }
            .padding(28)
        }
        .frame(width: 380)
        .background(Color(red: 0.97, green: 0.95, blue: 0.92))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Multi-Verse Share Card

struct MultiVerseShareCardView: View {
    let reference: String       // e.g., "Genesis 1:1-3"
    let verses: [(number: Int, text: String)]
    let scriptureName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top accent bar
            Rectangle()
                .fill(Color(red: 0.75, green: 0.38, blue: 0.28))
                .frame(height: 6)

            VStack(alignment: .leading, spacing: 20) {
                // Reference header
                VStack(alignment: .leading, spacing: 6) {
                    Text(reference)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.28))

                    Text(scriptureName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.55, green: 0.50, blue: 0.45))
                }

                // Verses
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(verses, id: \.number) { verse in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(verse.number)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.28))
                                .frame(width: 24, alignment: .trailing)

                            Text(verse.text)
                                .font(.custom("Georgia", size: 17))
                                .foregroundColor(Color(red: 0.12, green: 0.10, blue: 0.08))
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer(minLength: 16)

                // Footer
                HStack {
                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                        Text("Shared via Seek")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.28).opacity(0.6))
                }
            }
            .padding(28)
        }
        .frame(width: 380)
        .background(Color(red: 0.97, green: 0.95, blue: 0.92))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Share Image Generator

@MainActor
class ShareImageGenerator {

    static let shared = ShareImageGenerator()

    private init() {}

    /// Generate a share image based on content type
    func generateImage(for content: ShareContent) -> UIImage? {
        let view: AnyView

        switch content.contentType {
        case .highlight:
            view = AnyView(
                HighlightShareCardView(content: content)
                    .padding(20)
                    .background(Color.clear)
            )
        case .note, .verse, .guidedInsight:
            view = AnyView(
                ShareCardView(content: content)
                    .padding(20)
                    .background(Color.clear)
            )
        case .multiVerse:
            // Multi-verse has its own method
            return nil
        }

        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale

        return renderer.uiImage
    }

    /// Generate a share image for multiple verses
    func generateMultiVerseImage(
        reference: String,
        verses: [(number: Int, text: String)],
        scriptureName: String
    ) -> UIImage? {
        let view = MultiVerseShareCardView(
            reference: reference,
            verses: verses,
            scriptureName: scriptureName
        )
        .padding(20)
        .background(Color.clear)

        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale

        return renderer.uiImage
    }

    /// Present the iOS share sheet with the generated image
    func shareImage(_ image: UIImage, from viewController: UIViewController? = nil) {
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        // Get the presenting view controller
        let presenter = viewController ?? Self.topViewController()

        // iPad support
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter?.view
            popover.sourceRect = CGRect(
                x: presenter?.view.bounds.midX ?? 0,
                y: presenter?.view.bounds.midY ?? 0,
                width: 0,
                height: 0
            )
        }

        presenter?.present(activityVC, animated: true)
    }

    /// Share a single verse with optional note
    func shareSingleVerse(
        reference: String,
        verseText: String,
        scriptureName: String,
        noteText: String? = nil
    ) {
        let content = ShareContent(
            reference: reference,
            verseText: verseText,
            scriptureName: scriptureName,
            noteText: noteText,
            contentType: noteText != nil ? .note : .verse
        )

        guard let image = generateImage(for: content) else {
            print("[ShareImageGenerator] Failed to generate image")
            return
        }

        shareImage(image)
    }

    /// Share a highlight (branded card with highlight styling)
    func shareHighlight(
        reference: String,
        verseText: String,
        scriptureName: String
    ) {
        let content = ShareContent(
            reference: reference,
            verseText: verseText,
            scriptureName: scriptureName,
            noteText: nil,
            contentType: .highlight
        )

        guard let image = generateImage(for: content) else {
            print("[ShareImageGenerator] Failed to generate highlight image")
            return
        }

        shareImage(image)
    }

    /// Share a note (branded card with note styling)
    func shareNote(
        reference: String,
        verseText: String,
        scriptureName: String,
        noteText: String
    ) {
        let content = ShareContent(
            reference: reference,
            verseText: verseText,
            scriptureName: scriptureName,
            noteText: noteText,
            contentType: .note
        )

        guard let image = generateImage(for: content) else {
            print("[ShareImageGenerator] Failed to generate note image")
            return
        }

        shareImage(image)
    }

    /// Share a JourneyRecord (highlight or note)
    func shareJourneyRecord(_ record: JourneyRecord) {
        switch record.type {
        case .highlight:
            shareHighlight(
                reference: record.reference,
                verseText: record.verseText,
                scriptureName: record.textName
            )
        case .note:
            shareNote(
                reference: record.reference,
                verseText: record.verseText,
                scriptureName: record.textName,
                noteText: record.noteText ?? ""
            )
        }
    }

    /// Share multiple verses
    func shareMultipleVerses(
        bookName: String,
        chapterNumber: Int,
        verses: [(number: Int, text: String)],
        scriptureName: String
    ) {
        guard !verses.isEmpty else { return }

        let sortedVerses = verses.sorted { $0.number < $1.number }
        let firstVerse = sortedVerses.first!.number
        let lastVerse = sortedVerses.last!.number

        let reference: String
        if firstVerse == lastVerse {
            reference = "\(bookName) \(chapterNumber):\(firstVerse)"
        } else {
            reference = "\(bookName) \(chapterNumber):\(firstVerse)-\(lastVerse)"
        }

        guard let image = generateMultiVerseImage(
            reference: reference,
            verses: sortedVerses,
            scriptureName: scriptureName
        ) else {
            print("[ShareImageGenerator] Failed to generate multi-verse image")
            return
        }

        shareImage(image)
    }

    // MARK: - Helper

    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }

        var topController = window.rootViewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        return topController
    }
}

// MARK: - Copy Utilities

struct CopyUtility {

    /// Copy a verse to clipboard (plain text, no branding)
    static func copyVerse(reference: String, verseText: String, scriptureName: String) {
        let text = "\(reference) – \(scriptureName)\n\n\(verseText)"
        UIPasteboard.general.string = text
    }

    /// Copy a highlight to clipboard (plain text, no branding)
    static func copyHighlight(reference: String, verseText: String, scriptureName: String) {
        let text = "\(reference) – \(scriptureName)\n\n\(verseText)"
        UIPasteboard.general.string = text
    }

    /// Copy a note to clipboard (plain text, no branding)
    static func copyNote(reference: String, verseText: String, scriptureName: String, noteText: String) {
        var text = "\(reference) – \(scriptureName)\n\n\(verseText)"
        if !noteText.isEmpty {
            text += "\n\n\(noteText)"
        }
        UIPasteboard.general.string = text
    }

    /// Copy a JourneyRecord to clipboard
    static func copyJourneyRecord(_ record: JourneyRecord) {
        switch record.type {
        case .highlight:
            copyHighlight(
                reference: record.reference,
                verseText: record.verseText,
                scriptureName: record.textName
            )
        case .note:
            copyNote(
                reference: record.reference,
                verseText: record.verseText,
                scriptureName: record.textName,
                noteText: record.noteText ?? ""
            )
        }
    }
}

// MARK: - Preview

#Preview("Share Card") {
    ShareCardView(content: ShareContent(
        reference: "Genesis 1:1",
        verseText: "In the beginning God created the heaven and the earth.",
        scriptureName: "Bible (KJV)",
        noteText: "The foundation of everything - a reminder that all things have a beginning."
    ))
    .padding(40)
    .background(Color.gray.opacity(0.2))
}

#Preview("Highlight Card") {
    HighlightShareCardView(content: ShareContent(
        reference: "Genesis 1:1",
        verseText: "In the beginning God created the heaven and the earth.",
        scriptureName: "Bible (KJV)",
        contentType: .highlight
    ))
    .padding(40)
    .background(Color.gray.opacity(0.2))
}

#Preview("Multi-Verse Card") {
    MultiVerseShareCardView(
        reference: "Genesis 1:1-3",
        verses: [
            (1, "In the beginning God created the heaven and the earth."),
            (2, "And the earth was without form, and void; and darkness was upon the face of the deep."),
            (3, "And God said, Let there be light: and there was light.")
        ],
        scriptureName: "Bible (KJV)"
    )
    .padding(40)
    .background(Color.gray.opacity(0.2))
}
