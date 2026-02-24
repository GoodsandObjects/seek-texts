import SwiftUI
import UIKit

enum GuidedStudyShareOption {
    case passageOnly
    case passageWithReflection
    case reflectionOnly
}

@MainActor
final class ShareManager {
    static let shared = ShareManager()

    func generateCardImage(payload: ShareCardPayload) -> UIImage? {
        let view = ShareCardView(payload: payload)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        return renderer.uiImage
    }

    func generateStreakCardImage(
        currentStreak: Int,
        isQualifiedToday: Bool,
        milestoneCopy: String?
    ) -> UIImage? {
        let view = StreakShareCardView(
            currentStreak: currentStreak,
            milestoneCopy: milestoneCopy,
            isQualifiedToday: isQualifiedToday
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        return renderer.uiImage
    }

    func generateGuidedStudyCardImage(
        reference: String,
        excerpt: String?,
        reflection: String?
    ) -> UIImage? {
        let view = GuidedStudyShareCardView(
            reference: reference,
            excerpt: excerpt,
            reflection: reflection
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        return renderer.uiImage
    }

    func generateVerseCardImage(
        verseText: String,
        referenceText: String,
        sourceText: String?
    ) -> UIImage? {
        let cardSize = CGSize(width: 1080, height: 1350)
        let view = VerseShareCardView(
            verseText: verseText,
            referenceText: referenceText,
            sourceText: sourceText
        )
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        renderer.proposedSize = ProposedViewSize(width: cardSize.width, height: cardSize.height)
        guard let rawImage = renderer.uiImage else { return nil }

        // Redraw into an opaque bitmap so the share sheet always sees a filled background.
        let opaqueFormat = UIGraphicsImageRendererFormat()
        opaqueFormat.scale = rawImage.scale
        opaqueFormat.opaque = true
        let opaqueRenderer = UIGraphicsImageRenderer(size: rawImage.size, format: opaqueFormat)
        return opaqueRenderer.image { ctx in
            UIColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: rawImage.size))
            rawImage.draw(at: .zero)
        }
    }

    func shareSingleVerse(
        reference: String,
        verseText: String,
        scriptureName: String,
        caption: String? = nil,
        isHighlighted: Bool = false
    ) {
        let payload = ShareCardPayload(
            reference: reference,
            verseText: verseText,
            scriptureName: scriptureName,
            caption: caption,
            isHighlighted: isHighlighted
        )
        sharePayload(payload, prefilledCaption: caption)
    }

    func shareMultipleVerses(
        bookName: String,
        chapterNumber: Int,
        verses: [(number: Int, text: String)],
        scriptureName: String
    ) {
        guard !verses.isEmpty else { return }
        let sorted = verses.sorted { $0.number < $1.number }
        let first = sorted.first?.number ?? chapterNumber
        let last = sorted.last?.number ?? chapterNumber
        let reference = first == last
            ? "\(bookName) \(chapterNumber):\(first)"
            : "\(bookName) \(chapterNumber):\(first)-\(last)"
        let combinedText = sorted
            .map { "\($0.number). \($0.text)" }
            .joined(separator: "\n\n")

        let payload = ShareCardPayload(
            reference: reference,
            verseText: combinedText,
            scriptureName: scriptureName,
            caption: nil,
            isHighlighted: false
        )
        sharePayload(payload, prefilledCaption: nil)
    }

    func shareJourneyRecord(_ record: JourneyRecord) {
        switch record.type {
        case .highlight:
            shareSingleVerse(
                reference: record.reference,
                verseText: record.verseText,
                scriptureName: record.textName,
                caption: record.noteText,
                isHighlighted: true
            )
        case .note:
            shareSingleVerse(
                reference: record.reference,
                verseText: record.verseText,
                scriptureName: record.textName,
                caption: record.noteText,
                isHighlighted: false
            )
        }
    }

    func shareStreak(
        currentStreak: Int,
        isQualifiedToday: Bool,
        milestoneCopy: String?
    ) {
        guard let image = generateStreakCardImage(
            currentStreak: currentStreak,
            isQualifiedToday: isQualifiedToday,
            milestoneCopy: milestoneCopy
        ) else {
            return
        }

        presentShareSheet(image: image, caption: nil)
    }

    func shareGuidedStudy(
        reference: String,
        passageText: String,
        reflectionText: String?,
        option: GuidedStudyShareOption
    ) {
        let cleanedReference = cleanedText(reference)
        let cleanedPassage = cleanedText(passageText)
        let cleanedReflection = cleanedText(reflectionText)
        guard !cleanedPassage.isEmpty || !cleanedReflection.isEmpty else { return }

        let safeExcerpt = makeExcerpt(from: cleanedPassage, sentenceLimit: 3, maxCharacters: 320)
        let safeReflection = truncateText(cleanedReflection, maxCharacters: 500)
        let hasMeaningfulReflection = cleanedReflection.count >= 20

        let excerpt: String?
        let reflection: String?
        switch option {
        case .passageOnly:
            excerpt = safeExcerpt
            reflection = nil
        case .passageWithReflection:
            excerpt = safeExcerpt
            reflection = hasMeaningfulReflection ? safeReflection : nil
        case .reflectionOnly:
            // Short/empty reflections degrade to passage-only to avoid noisy cards.
            if hasMeaningfulReflection {
                excerpt = nil
                reflection = safeReflection
            } else {
                excerpt = safeExcerpt
                reflection = nil
            }
        }

        let effectiveExcerpt = truncateText(excerpt, maxCharacters: 320)
        let effectiveReference = cleanedReference.isEmpty ? "Guided Passage" : cleanedReference
        guard let image = generateGuidedStudyCardImage(
            reference: effectiveReference,
            excerpt: effectiveExcerpt,
            reflection: reflection
        ) else {
            return
        }

        presentGuidedStudyShareSheet(image: image, reference: cleanedReference)
    }

    func shareVerseCard(
        verseText: String,
        referenceText: String,
        sourceText: String? = nil
    ) {
        let cleanedVerse = cleanedText(verseText)
        let cleanedReference = cleanedText(referenceText)
        let cleanedSource = cleanedText(sourceText)
        guard !cleanedVerse.isEmpty, !cleanedReference.isEmpty else { return }

        guard let image = generateVerseCardImage(
            verseText: cleanedVerse,
            referenceText: cleanedReference,
            sourceText: cleanedSource.isEmpty ? nil : cleanedSource
        ) else {
            return
        }

        presentVerseCardShareSheet(image: image, referenceText: cleanedReference)
    }

    private func sharePayload(_ payload: ShareCardPayload, prefilledCaption: String?) {
        guard let image = generateCardImage(payload: payload) else {
            return
        }

        presentShareSheet(image: image, caption: prefilledCaption)
    }

    private func presentShareSheet(image: UIImage, caption: String?) {
        var items: [Any] = [image]
        if let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
            items.append(caption)
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let presenter = Self.sharePresenter() else { return }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
        }

        presenter.present(activityVC, animated: true)
    }

    private func presentVerseCardShareSheet(image: UIImage, referenceText: String) {
        let metadata = verseShareMetadata(from: referenceText)
        guard let fileURL = writeVerseCardJPEGToTemporaryFile(image: image, filename: metadata.filename) else { return }
        let items: [Any] = [fileURL, metadata.previewText]

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.setValue(metadata.subject, forKey: "subject")
        guard let presenter = Self.sharePresenter() else { return }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
        }

        presenter.present(activityVC, animated: true)
    }

    private func presentGuidedStudyShareSheet(image: UIImage, reference: String) {
        let fileURL = guidedStudyShareFileURL(reference: reference)
        var items: [Any]

        if let pngData = image.pngData() {
            do {
                try pngData.write(to: fileURL, options: .atomic)
                items = [fileURL]
            } catch {
                items = [image]
            }
        } else {
            items = [image]
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let presenter = Self.sharePresenter() else { return }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
        }

        presenter.present(activityVC, animated: true)
    }

    private func guidedStudyShareFileURL(reference: String) -> URL {
        let filename: String
        if let safeReference = sanitizeFilenameReference(reference), !safeReference.isEmpty {
            filename = "Seek — \(safeReference).png"
        } else {
            filename = "Seek.png"
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private func writeVerseCardJPEGToTemporaryFile(image: UIImage, filename: String) -> URL? {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        guard let jpegData = image.jpegData(compressionQuality: 0.94) else {
            return nil
        }

        do {
            try jpegData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private func verseShareMetadata(from reference: String) -> (subject: String, filename: String, previewText: String) {
        let cleanedReference = cleanedText(reference)
        let pattern = "(\\d+):(\\d+)"
        let nsRange = NSRange(cleanedReference.startIndex..<cleanedReference.endIndex, in: cleanedReference)

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: cleanedReference, range: nsRange),
           let chapterRange = Range(match.range(at: 1), in: cleanedReference),
           let verseRange = Range(match.range(at: 2), in: cleanedReference),
           let fullRange = Range(match.range(at: 0), in: cleanedReference) {
            let chapter = String(cleanedReference[chapterRange])
            let verse = String(cleanedReference[verseRange])
            let rawBook = cleanedReference[..<fullRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let book = rawBook.isEmpty ? "Verse" : rawBook
            let subject = "\(book) \(chapter):\(verse)"
            let safeBook = sanitizeUnderscoreFilename(book)
            let filename = "\(safeBook)_\(chapter)_\(verse).jpg"
            return (subject: subject, filename: filename, previewText: "\(subject) — Seek")
        }

        let fallbackSubject = cleanedReference.isEmpty ? "Verse" : cleanedReference
        let fallbackName = sanitizeUnderscoreFilename(fallbackSubject)
        return (
            subject: fallbackSubject,
            filename: "\(fallbackName).jpg",
            previewText: "\(fallbackSubject) — Seek"
        )
    }

    private func sanitizeUnderscoreFilename(_ value: String) -> String {
        let replaced = value
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return replaced.isEmpty ? "Verse" : replaced
    }

    private func sanitizeFilenameReference(_ value: String) -> String? {
        let cleaned = cleanedText(value)
        guard !cleaned.isEmpty else { return nil }

        let filtered = cleaned
            .replacingOccurrences(of: "[^A-Za-z0-9 ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filtered.isEmpty else { return nil }

        let titleCased = filtered.capitalized
        let maxLength = 48
        if titleCased.count <= maxLength {
            return titleCased
        }
        let index = titleCased.index(titleCased.startIndex, offsetBy: maxLength)
        return String(titleCased[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanedText(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeExcerpt(from passage: String, sentenceLimit: Int = 3, maxCharacters: Int = 320) -> String {
        let cleaned = cleanedText(passage)
        guard !cleaned.isEmpty else { return "" }

        let pattern = "(?<=[.!?])\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return truncateText(cleaned, maxCharacters: maxCharacters) ?? ""
        }

        let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        let matches = regex.matches(in: cleaned, range: nsRange)

        var parts: [String] = []
        var start = cleaned.startIndex
        for match in matches {
            guard let splitRange = Range(match.range, in: cleaned) else { continue }
            let sentence = cleaned[start..<splitRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                parts.append(sentence)
            }
            start = splitRange.upperBound
        }

        let tail = cleaned[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            parts.append(tail)
        }

        if parts.isEmpty {
            return truncateText(cleaned, maxCharacters: maxCharacters) ?? ""
        }

        let excerpt = parts.prefix(sentenceLimit).joined(separator: " ")
        return truncateText(excerpt, maxCharacters: maxCharacters) ?? ""
    }

    private func truncateText(_ text: String?, maxCharacters: Int) -> String? {
        guard let text else { return nil }
        let cleaned = cleanedText(text)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count > maxCharacters else { return cleaned }

        let endIndex = cleaned.index(cleaned.startIndex, offsetBy: max(0, maxCharacters - 1))
        let trimmed = cleaned[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmed)…"
    }

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

    private static func sharePresenter() -> UIViewController? {
        guard var topController = topViewController() else { return nil }
        while topController is UIAlertController, let presenting = topController.presentingViewController {
            topController = presenting
        }
        return topController
    }
}
