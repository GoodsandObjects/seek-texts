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

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let freeDailyLimit = 1

    private let shareCountKey = "seek_share_count_day"
    private let shareDateKey = "seek_share_count_date"
    private let streakShareCountKey = "seek_streak_share_count_day"
    private let streakShareDateKey = "seek_streak_share_count_date"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar
    }

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
        guard canShareStreakNow() else {
            presentStreakShareLimitPaywall()
            return
        }

        guard let image = generateStreakCardImage(
            currentStreak: currentStreak,
            isQualifiedToday: isQualifiedToday,
            milestoneCopy: milestoneCopy
        ) else {
            #if DEBUG
            print("[ShareManager] Failed to render streak share card image")
            #endif
            return
        }

        incrementStreakShareUsageIfNeeded()
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
            #if DEBUG
            print("[ShareManager] Failed to render guided study share card image")
            #endif
            return
        }

        presentGuidedStudyShareSheet(image: image, reference: cleanedReference)
    }

    private func sharePayload(_ payload: ShareCardPayload, prefilledCaption: String?) {
        guard canShareNow() else {
            presentShareLimitPaywall()
            return
        }

        guard let image = generateCardImage(payload: payload) else {
            #if DEBUG
            print("[ShareManager] Failed to render share card image")
            #endif
            return
        }

        incrementShareUsageIfNeeded()
        presentShareSheet(image: image, caption: prefilledCaption)
    }

    private func canShareNow() -> Bool {
        if EntitlementManager.shared.isPremium {
            return true
        }
        let today = dayString(for: Date())
        if defaults.string(forKey: shareDateKey) != today {
            return true
        }
        let count = defaults.integer(forKey: shareCountKey)
        return count < freeDailyLimit
    }

    private func incrementShareUsageIfNeeded() {
        guard !EntitlementManager.shared.isPremium else { return }

        let today = dayString(for: Date())
        let savedDay = defaults.string(forKey: shareDateKey)
        if savedDay == today {
            defaults.set(defaults.integer(forKey: shareCountKey) + 1, forKey: shareCountKey)
        } else {
            defaults.set(today, forKey: shareDateKey)
            defaults.set(1, forKey: shareCountKey)
        }
    }

    private func canShareStreakNow() -> Bool {
        if EntitlementManager.shared.isPremium {
            return true
        }
        let today = dayString(for: Date())
        if defaults.string(forKey: streakShareDateKey) != today {
            return true
        }
        let count = defaults.integer(forKey: streakShareCountKey)
        return count < freeDailyLimit
    }

    private func incrementStreakShareUsageIfNeeded() {
        guard !EntitlementManager.shared.isPremium else { return }

        let today = dayString(for: Date())
        let savedDay = defaults.string(forKey: streakShareDateKey)
        if savedDay == today {
            defaults.set(defaults.integer(forKey: streakShareCountKey) + 1, forKey: streakShareCountKey)
        } else {
            defaults.set(today, forKey: streakShareDateKey)
            defaults.set(1, forKey: streakShareCountKey)
        }
    }

    private func presentShareSheet(image: UIImage, caption: String?) {
        var items: [Any] = [image]
        if let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
            items.append(caption)
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let presenter = Self.topViewController() else { return }

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
                #if DEBUG
                assert(image.size.width > 0 && image.size.height > 0, "[ShareManager] Guided study share image has invalid size")
                let exists = FileManager.default.fileExists(atPath: fileURL.path)
                print("[ShareManager] Guided study image size: \(Int(image.size.width))x\(Int(image.size.height))")
                print("[ShareManager] Guided study file exists at \(fileURL.path): \(exists)")
                #endif
            } catch {
                #if DEBUG
                print("[ShareManager] Failed writing guided study share PNG to disk: \(error.localizedDescription)")
                print("[ShareManager] Guided study image size: \(Int(image.size.width))x\(Int(image.size.height))")
                #endif
                items = [image]
            }
        } else {
            #if DEBUG
            print("[ShareManager] Failed to encode guided study image as PNG")
            print("[ShareManager] Guided study image size: \(Int(image.size.width))x\(Int(image.size.height))")
            #endif
            items = [image]
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let presenter = Self.topViewController() else { return }

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

    private func presentShareLimitPaywall() {
        guard let presenter = Self.topViewController() else { return }
        let paywall = PaywallView(context: .shareLimit, streakDays: StreakStore().load()?.currentStreak ?? 0) { }
        let host = UIHostingController(rootView: paywall)
        host.modalPresentationStyle = .fullScreen
        presenter.present(host, animated: true)
    }

    private func presentStreakShareLimitPaywall() {
        guard let presenter = Self.topViewController() else { return }
        let paywall = PaywallView(
            context: .shareLimit,
            streakDays: StreakStore().load()?.currentStreak ?? 0,
            customSubtitle: "Share without limits."
        ) { }
        let host = UIHostingController(rootView: paywall)
        host.modalPresentationStyle = .fullScreen
        presenter.present(host, animated: true)
    }

    private func dayString(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
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
}
