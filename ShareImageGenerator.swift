import UIKit

@MainActor
final class ShareImageGenerator {
    static let shared = ShareImageGenerator()

    private init() {}

    func shareSingleVerse(
        reference: String,
        verseText: String,
        scriptureName: String,
        noteText: String? = nil
    ) {
        ShareManager.shared.shareSingleVerse(
            reference: reference,
            verseText: verseText,
            scriptureName: scriptureName,
            caption: noteText,
            isHighlighted: false
        )
    }

    func shareHighlight(
        reference: String,
        verseText: String,
        scriptureName: String
    ) {
        ShareManager.shared.shareSingleVerse(
            reference: reference,
            verseText: verseText,
            scriptureName: scriptureName,
            caption: nil,
            isHighlighted: true
        )
    }

    func shareNote(
        reference: String,
        verseText: String,
        scriptureName: String,
        noteText: String
    ) {
        ShareManager.shared.shareSingleVerse(
            reference: reference,
            verseText: verseText,
            scriptureName: scriptureName,
            caption: noteText,
            isHighlighted: false
        )
    }

    func shareJourneyRecord(_ record: JourneyRecord) {
        ShareManager.shared.shareJourneyRecord(record)
    }

    func shareMultipleVerses(
        bookName: String,
        chapterNumber: Int,
        verses: [(number: Int, text: String)],
        scriptureName: String
    ) {
        ShareManager.shared.shareMultipleVerses(
            bookName: bookName,
            chapterNumber: chapterNumber,
            verses: verses,
            scriptureName: scriptureName
        )
    }
}

struct CopyUtility {
    static func copyVerse(reference: String, verseText: String, scriptureName: String) {
        let text = "\(reference) – \(scriptureName)\n\n\(verseText)"
        UIPasteboard.general.string = text
    }

    static func copyHighlight(reference: String, verseText: String, scriptureName: String) {
        copyVerse(reference: reference, verseText: verseText, scriptureName: scriptureName)
    }

    static func copyNote(reference: String, verseText: String, scriptureName: String, noteText: String) {
        var text = "\(reference) – \(scriptureName)\n\n\(verseText)"
        if !noteText.isEmpty {
            text += "\n\n\(noteText)"
        }
        UIPasteboard.general.string = text
    }

    static func copyJourneyRecord(_ record: JourneyRecord) {
        switch record.type {
        case .highlight:
            copyHighlight(reference: record.reference, verseText: record.verseText, scriptureName: record.textName)
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
