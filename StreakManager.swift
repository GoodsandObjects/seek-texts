import Foundation
import Combine
import UIKit

@MainActor
final class StreakManager: ObservableObject {
    static let shared = StreakManager()

    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var lastQualifiedDate: Date?
    @Published private(set) var isQualifiedToday: Bool = false
    @Published private(set) var lastMilestoneAchieved: StreakMilestoneAchievement?
    @Published private(set) var lastMilestoneAchievedDate: Date?
    @Published private(set) var lastMilestoneType: StreakMilestone?
    @Published private(set) var qualifiedDates: [Date] = []

    @Published private(set) var versesReadToday: Int = 0
    @Published private(set) var verseIdsReadToday: Set<String> = []
    @Published private(set) var activeReadingSecondsToday: TimeInterval = 0
    @Published private(set) var reflectionsToday: Int = 0

    // Compatibility surface for existing call sites.
    @Published private(set) var secondsSpentToday: TimeInterval = 0
    @Published private(set) var notesOrHighlightsToday: Int = 0

    var shouldShowMilestoneCopy: Bool {
        guard let lastMilestoneAchieved else { return false }
        return Date().timeIntervalSince(lastMilestoneAchieved.achievedAt) <= 24 * 60 * 60
    }

    var milestoneCopyText: String? {
        guard shouldShowMilestoneCopy else { return nil }
        return lastMilestoneAchieved?.milestone.acknowledgementText
    }

    var longestStreakCount: Int {
        longestStreak
    }

    var totalQualifiedDaysCount: Int {
        max(totalEngagedDays, qualifiedDates.count)
    }

    private var longestStreak: Int = 0
    private var totalEngagedDays: Int = 0
    private var firstEngagedAt: Date?
    private var lastEngagedSource: StreakEngagementSource?
    private var lastActivityDate: Date?
    private var todayCountersDate: Date

    private var visibleVerseSince: [String: Date] = [:]
    private var lastReaderInteractionAt: Date?

    private var isReaderVisible = false
    private var isReaderContentVisible = false
    private var isAppActive = true
    private var activeReadingStart: Date?
    private var readingTimer: Timer?

    private let defaults: UserDefaults
    private let calendar: Calendar

    private let verseQualificationThreshold = 5
    private let activeReadingQualificationSeconds: TimeInterval = 240
    private let reflectionQualificationThreshold = 1
    private let verseVisibleMinimumSeconds: TimeInterval = 8
    private let readerIdleTimeoutSeconds: TimeInterval = 20

    private struct PersistedState: Codable {
        let currentStreak: Int
        let longestStreak: Int
        let totalEngagedDays: Int
        let firstEngagedAt: Date?
        let lastQualifiedDate: Date?
        let lastEngagedSource: StreakEngagementSource?
        let lastActivityDate: Date?
        let todayCountersDate: Date
        let verseIdsReadToday: [String]
        let activeReadingSecondsToday: TimeInterval
        let reflectionsToday: Int
        let lastMilestoneAchieved: StreakMilestoneAchievement?
        let lastMilestoneAchievedDate: Date?
        let lastMilestoneType: StreakMilestone?
        let qualifiedDates: [Date]?
    }

    private struct LegacyManagerStateV1: Codable {
        let currentStreak: Int
        let longestStreak: Int
        let totalEngagedDays: Int
        let firstEngagedAt: Date?
        let lastQualifiedDate: Date?
        let lastEngagedSource: StreakEngagementSource?
        let dayAnchor: Date
        let versesReadToday: Int
        let secondsSpentToday: TimeInterval
        let notesOrHighlightsToday: Int
        let verseIdsReadToday: [String]
    }

    private enum DailyQualificationCondition: String {
        case verses = "5 distinct verses"
        case activeReading = "4 minutes active reading"
        case reflection = "note/highlight reflection"
    }

    private let stateKey = "seek_streak_manager_state_v2"
    private let priorStateKey = "seek_streak_manager_state_v1"
    private let legacyKey = "seek_streak_state_v1"
    private let firstDayModalShownKey = "seek_streak_first_day_modal_shown_v1"
    private let firstDayModalPendingKey = "seek_streak_first_day_modal_pending_v1"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar
        self.todayCountersDate = calendar.startOfDay(for: Date())

        loadState()
        installLifecycleObservers()
        synchronizeToToday(referenceDate: Date())
        refreshQualifiedTodayState(referenceDate: Date())
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        readingTimer?.invalidate()
    }

    func readerDidAppear() {
        isReaderVisible = true
        synchronizeToToday(referenceDate: Date())
        startReadingClockIfNeeded()
    }

    func readerDidDisappear() {
        flushActiveReadingTime()
        visibleVerseSince.removeAll()
        isReaderVisible = false
        isReaderContentVisible = false
        stopReadingClock()
    }

    func setReaderContentVisible(_ visible: Bool) {
        synchronizeToToday(referenceDate: Date())
        isReaderContentVisible = visible
        if visible {
            startReadingClockIfNeeded()
        } else {
            flushActiveReadingTime()
            visibleVerseSince.removeAll()
            if !isReaderVisible {
                stopReadingClock()
            }
        }
    }

    func recordReaderInteraction(at date: Date = Date()) {
        synchronizeToToday(referenceDate: date)
        lastReaderInteractionAt = date
        lastActivityDate = date
        processVisibleVerses(referenceDate: date)
        startReadingClockIfNeeded()
        persistState()
    }

    func recordVerseBecameVisible(verseId: String, at date: Date = Date()) {
        synchronizeToToday(referenceDate: date)
        recordReaderInteraction(at: date)
        if visibleVerseSince[verseId] == nil {
            visibleVerseSince[verseId] = date
        }
        processVisibleVerses(referenceDate: date)
    }

    func recordVerseNoLongerVisible(verseId: String, at date: Date = Date()) {
        synchronizeToToday(referenceDate: date)
        recordReaderInteraction(at: date)
        guard let firstSeenAt = visibleVerseSince.removeValue(forKey: verseId) else { return }
        guard date.timeIntervalSince(firstSeenAt) >= verseVisibleMinimumSeconds else { return }
        markVerseRead(verseId: verseId, at: date)
    }

    // Verse interaction qualifies even before 8s visibility (explicit intent).
    func recordVerseInteraction(verseId: String, at date: Date = Date()) {
        synchronizeToToday(referenceDate: date)
        recordReaderInteraction(at: date)
        markVerseRead(verseId: verseId, at: date)
    }

    // Backward compatibility for older call sites.
    func recordVerseVisibility(verseId: String, at date: Date = Date()) {
        recordVerseInteraction(verseId: verseId, at: date)
    }

    func recordNoteCreation(at date: Date = Date()) {
        synchronizeToToday(referenceDate: date)
        lastActivityDate = date
            reflectionsToday += 1
            syncCounterAliases()
            persistState()
            debugLogCounters(reason: "note_created")
            updateStreakIfQualified(referenceDate: date)
    }

    func recordHighlightCreation(at date: Date = Date()) {
        synchronizeToToday(referenceDate: date)
        lastActivityDate = date
            reflectionsToday += 1
            syncCounterAliases()
            persistState()
            debugLogCounters(reason: "highlight_created")
            updateStreakIfQualified(referenceDate: date)
    }

    func evaluateDailyQualification() -> Bool {
        qualificationCondition() != nil
    }

    func updateStreakIfQualified() {
        updateStreakIfQualified(referenceDate: Date())
    }

    func resetIfMissedDay() {
        resetIfMissedDay(referenceDate: Date())
    }

    func applyLegacyDebugState(_ state: StreakState) {
        currentStreak = state.currentStreak
        longestStreak = state.longestStreak
        totalEngagedDays = state.totalEngagedDays
        firstEngagedAt = state.firstEngagedAt
        lastQualifiedDate = state.lastEngagedAt.map { calendar.startOfDay(for: $0) }
        lastEngagedSource = state.lastEngagedSource
        lastActivityDate = state.lastEngagedAt
        synchronizeToToday(referenceDate: Date())
        refreshQualifiedTodayState(referenceDate: Date())
        persistState()
        persistLegacySnapshot(lastEngagedAt: state.lastEngagedAt)
        NotificationCenter.default.post(name: .streakDidUpdate, object: nil)
    }

    func debugResetAll() {
        currentStreak = 0
        longestStreak = 0
        totalEngagedDays = 0
        firstEngagedAt = nil
        lastQualifiedDate = nil
        lastEngagedSource = nil
        lastActivityDate = nil
        lastMilestoneAchieved = nil
        lastMilestoneAchievedDate = nil
        lastMilestoneType = nil
        qualifiedDates = []
        todayCountersDate = calendar.startOfDay(for: Date())
        verseIdsReadToday = []
        versesReadToday = 0
        activeReadingSecondsToday = 0
        reflectionsToday = 0
        syncCounterAliases()
        visibleVerseSince = [:]
        lastReaderInteractionAt = nil
        activeReadingStart = nil
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: priorStateKey)
        defaults.removeObject(forKey: legacyKey)
        defaults.removeObject(forKey: firstDayModalShownKey)
        defaults.removeObject(forKey: firstDayModalPendingKey)
        isQualifiedToday = false
        NotificationCenter.default.post(name: .streakDidUpdate, object: nil)
    }

    func consumeFirstQualificationModalFlag() -> Bool {
        if defaults.bool(forKey: firstDayModalShownKey) {
            defaults.set(false, forKey: firstDayModalPendingKey)
            return false
        }
        guard defaults.bool(forKey: firstDayModalPendingKey) else { return false }
        defaults.set(true, forKey: firstDayModalShownKey)
        defaults.set(false, forKey: firstDayModalPendingKey)
        return true
    }

    #if DEBUG
    enum DebugQualificationCondition {
        case verses
        case activeReading
        case reflection
    }

    func debugSimulateDayAdvance(by days: Int) {
        guard days != 0 else { return }
        let reference = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
        synchronizeToToday(referenceDate: reference)
        debugLogCounters(reason: "simulate_day_advance_\(days)")
    }

    func debugQualifyToday(using condition: DebugQualificationCondition) {
        let now = Date()
        synchronizeToToday(referenceDate: now)
        switch condition {
        case .verses:
            for index in 0..<verseQualificationThreshold {
                markVerseRead(verseId: "debug-verse-\(index)", at: now)
            }
        case .activeReading:
            activeReadingSecondsToday = activeReadingQualificationSeconds
            syncCounterAliases()
            persistState()
        case .reflection:
            reflectionsToday = max(reflectionsToday, reflectionQualificationThreshold)
            syncCounterAliases()
            persistState()
        }
        updateStreakIfQualified(referenceDate: now)
    }
    #endif

    private func installLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        isAppActive = true
        synchronizeToToday(referenceDate: Date())
        startReadingClockIfNeeded()
    }

    @objc private func appWillResignActive() {
        flushActiveReadingTime()
        isAppActive = false
    }

    @objc private func appDidEnterBackground() {
        flushActiveReadingTime()
        isAppActive = false
    }

    private func markVerseRead(verseId: String, at date: Date) {
        guard !verseId.isEmpty else { return }
        guard !verseIdsReadToday.contains(verseId) else { return }

        verseIdsReadToday.insert(verseId)
        versesReadToday = verseIdsReadToday.count
        lastActivityDate = date
        persistState()
        debugLogCounters(reason: "verse_read")
        updateStreakIfQualified(referenceDate: date)
    }

    private func startReadingClockIfNeeded() {
        guard isReaderVisible, isReaderContentVisible, isAppActive else { return }
        guard readingTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushActiveReadingTime()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        readingTimer = timer
    }

    private func stopReadingClock() {
        readingTimer?.invalidate()
        readingTimer = nil
        activeReadingStart = nil
    }

    private func isReaderActivelyEngaged(at date: Date) -> Bool {
        guard let lastReaderInteractionAt else { return false }
        return date.timeIntervalSince(lastReaderInteractionAt) <= readerIdleTimeoutSeconds
    }

    private func flushActiveReadingTime() {
        let now = Date()
        synchronizeToToday(referenceDate: now)
        processVisibleVerses(referenceDate: now)

        guard isReaderVisible, isReaderContentVisible, isAppActive, isReaderActivelyEngaged(at: now) else {
            activeReadingStart = nil
            return
        }

        guard let start = activeReadingStart else {
            activeReadingStart = now
            return
        }

        let elapsed = now.timeIntervalSince(start)
        guard elapsed > 0 else { return }

        activeReadingStart = now
        activeReadingSecondsToday += elapsed
        lastActivityDate = now
        syncCounterAliases()
        persistState()
        debugLogCounters(reason: "active_seconds_update")
        updateStreakIfQualified(referenceDate: now)
    }

    private func processVisibleVerses(referenceDate: Date) {
        guard !visibleVerseSince.isEmpty else { return }
        let matured = visibleVerseSince.compactMap { verseId, firstSeenAt -> String? in
            referenceDate.timeIntervalSince(firstSeenAt) >= verseVisibleMinimumSeconds ? verseId : nil
        }
        guard !matured.isEmpty else { return }
        matured.forEach { verseId in
            visibleVerseSince.removeValue(forKey: verseId)
            markVerseRead(verseId: verseId, at: referenceDate)
        }
    }

    private func updateStreakIfQualified(referenceDate: Date) {
        synchronizeToToday(referenceDate: referenceDate)
        guard let condition = qualificationCondition() else { return }

        let today = calendar.startOfDay(for: referenceDate)
        if let lastQualifiedDate, calendar.isDate(lastQualifiedDate, inSameDayAs: today) {
            return
        }

        if let lastQualifiedDate {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               calendar.isDate(lastQualifiedDate, inSameDayAs: yesterday) {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }

        checkForMilestoneAchievement(onStreakIncrement: currentStreak, at: referenceDate)

        lastQualifiedDate = today
        appendQualifiedDateIfNeeded(today)
        lastActivityDate = referenceDate
        longestStreak = max(longestStreak, currentStreak)
        totalEngagedDays += 1
        if firstEngagedAt == nil {
            firstEngagedAt = today
        }
        lastEngagedSource = .reader

        if totalEngagedDays == 1, !defaults.bool(forKey: firstDayModalShownKey) {
            defaults.set(true, forKey: firstDayModalPendingKey)
        }

        refreshQualifiedTodayState(referenceDate: today)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        persistState()
        persistLegacySnapshot(lastEngagedAt: referenceDate)
        debugLogCounters(reason: "qualified_day", condition: condition)
        NotificationCenter.default.post(name: .streakDidUpdate, object: nil)
    }

    private func qualificationCondition() -> DailyQualificationCondition? {
        if versesReadToday >= verseQualificationThreshold {
            return .verses
        }
        if activeReadingSecondsToday >= activeReadingQualificationSeconds {
            return .activeReading
        }
        if reflectionsToday >= reflectionQualificationThreshold {
            return .reflection
        }
        return nil
    }

    private func synchronizeToToday(referenceDate: Date) {
        let today = calendar.startOfDay(for: referenceDate)
        if !calendar.isDate(todayCountersDate, inSameDayAs: today) {
            todayCountersDate = today
            verseIdsReadToday = []
            versesReadToday = 0
            activeReadingSecondsToday = 0
            reflectionsToday = 0
            visibleVerseSince = [:]
            lastReaderInteractionAt = nil
            activeReadingStart = nil
            syncCounterAliases()
            persistState()
        }
        resetIfMissedDay(referenceDate: referenceDate)
        refreshQualifiedTodayState(referenceDate: referenceDate)
    }

    private func resetIfMissedDay(referenceDate: Date) {
        guard let lastQualifiedDate else { return }
        let today = calendar.startOfDay(for: referenceDate)
        let lastQualifiedDay = calendar.startOfDay(for: lastQualifiedDate)
        guard let dayDelta = calendar.dateComponents([.day], from: lastQualifiedDay, to: today).day else { return }
        guard dayDelta > 1, currentStreak != 0 else { return }

        currentStreak = 0
        refreshQualifiedTodayState(referenceDate: today)
        persistState()
        persistLegacySnapshot(lastEngagedAt: self.lastQualifiedDate)
        NotificationCenter.default.post(name: .streakDidUpdate, object: nil)
    }

    private func loadState() {
        if let data = defaults.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            currentStreak = decoded.currentStreak
            longestStreak = decoded.longestStreak
            totalEngagedDays = decoded.totalEngagedDays
            firstEngagedAt = decoded.firstEngagedAt
            lastQualifiedDate = decoded.lastQualifiedDate
            lastEngagedSource = decoded.lastEngagedSource
            lastActivityDate = decoded.lastActivityDate
            todayCountersDate = calendar.startOfDay(for: decoded.todayCountersDate)
            verseIdsReadToday = Set(decoded.verseIdsReadToday)
            versesReadToday = verseIdsReadToday.count
            activeReadingSecondsToday = decoded.activeReadingSecondsToday
            reflectionsToday = decoded.reflectionsToday
            lastMilestoneAchieved = decoded.lastMilestoneAchieved
            lastMilestoneAchievedDate = decoded.lastMilestoneAchievedDate
            lastMilestoneType = decoded.lastMilestoneType
            if let achievement = decoded.lastMilestoneAchieved {
                if lastMilestoneAchievedDate == nil {
                    lastMilestoneAchievedDate = calendar.startOfDay(for: achievement.achievedAt)
                }
                if lastMilestoneType == nil {
                    lastMilestoneType = achievement.milestone
                }
            }
            qualifiedDates = normalizeQualifiedDates(decoded.qualifiedDates ?? [])
            if qualifiedDates.isEmpty, let lastQualifiedDate = decoded.lastQualifiedDate {
                qualifiedDates = [calendar.startOfDay(for: lastQualifiedDate)]
            }
            syncCounterAliases()
            refreshQualifiedTodayState(referenceDate: Date())
            return
        }

        if let priorData = defaults.data(forKey: priorStateKey),
           let decoded = try? JSONDecoder().decode(LegacyManagerStateV1.self, from: priorData) {
            currentStreak = decoded.currentStreak
            longestStreak = decoded.longestStreak
            totalEngagedDays = decoded.totalEngagedDays
            firstEngagedAt = decoded.firstEngagedAt
            lastQualifiedDate = decoded.lastQualifiedDate
            lastEngagedSource = decoded.lastEngagedSource
            lastActivityDate = decoded.lastQualifiedDate
            todayCountersDate = calendar.startOfDay(for: decoded.dayAnchor)
            verseIdsReadToday = Set(decoded.verseIdsReadToday)
            versesReadToday = max(decoded.versesReadToday, verseIdsReadToday.count)
            activeReadingSecondsToday = decoded.secondsSpentToday
            reflectionsToday = decoded.notesOrHighlightsToday
            lastMilestoneAchievedDate = nil
            lastMilestoneType = nil
            qualifiedDates = decoded.lastQualifiedDate.map { [calendar.startOfDay(for: $0)] } ?? []
            syncCounterAliases()
            refreshQualifiedTodayState(referenceDate: Date())
            persistState()
            persistLegacySnapshot(lastEngagedAt: decoded.lastQualifiedDate)
            return
        }

        if let legacyData = defaults.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode(StreakState.self, from: legacyData) {
            currentStreak = legacy.currentStreak
            longestStreak = legacy.longestStreak
            totalEngagedDays = legacy.totalEngagedDays
            firstEngagedAt = legacy.firstEngagedAt
            lastQualifiedDate = legacy.lastEngagedAt.map { calendar.startOfDay(for: $0) }
            lastEngagedSource = legacy.lastEngagedSource
            lastActivityDate = legacy.lastEngagedAt
            todayCountersDate = calendar.startOfDay(for: Date())
            lastMilestoneAchieved = nil
            lastMilestoneAchievedDate = nil
            lastMilestoneType = nil
            qualifiedDates = legacy.lastEngagedAt.map { [calendar.startOfDay(for: $0)] } ?? []
            syncCounterAliases()
            refreshQualifiedTodayState(referenceDate: Date())
            persistState()
            persistLegacySnapshot(lastEngagedAt: legacy.lastEngagedAt)
        }
    }

    private func refreshQualifiedTodayState(referenceDate: Date) {
        guard let lastQualifiedDate else {
            isQualifiedToday = false
            return
        }
        isQualifiedToday = calendar.isDate(lastQualifiedDate, inSameDayAs: referenceDate)
    }

    private func syncCounterAliases() {
        secondsSpentToday = activeReadingSecondsToday
        notesOrHighlightsToday = reflectionsToday
    }

    private func persistState() {
        let encoded = PersistedState(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalEngagedDays: totalEngagedDays,
            firstEngagedAt: firstEngagedAt,
            lastQualifiedDate: lastQualifiedDate,
            lastEngagedSource: lastEngagedSource,
            lastActivityDate: lastActivityDate,
            todayCountersDate: todayCountersDate,
            verseIdsReadToday: Array(verseIdsReadToday),
            activeReadingSecondsToday: activeReadingSecondsToday,
            reflectionsToday: reflectionsToday,
            lastMilestoneAchieved: lastMilestoneAchieved,
            lastMilestoneAchievedDate: lastMilestoneAchievedDate,
            lastMilestoneType: lastMilestoneType,
            qualifiedDates: qualifiedDates
        )
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        defaults.set(data, forKey: stateKey)
    }

    private func persistLegacySnapshot(lastEngagedAt: Date?) {
        let state = StreakState(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalEngagedDays: totalEngagedDays,
            firstEngagedAt: firstEngagedAt,
            lastEngagedAt: lastEngagedAt,
            lastEngagedSource: lastEngagedSource
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: legacyKey)
    }

    private func checkForMilestoneAchievement(onStreakIncrement streak: Int, at date: Date) {
        guard let milestone = StreakMilestone.matching(streak: streak) else { return }
        lastMilestoneAchieved = StreakMilestoneAchievement(milestone: milestone, achievedAt: date)
        lastMilestoneAchievedDate = calendar.startOfDay(for: date)
        lastMilestoneType = milestone
    }

    private func appendQualifiedDateIfNeeded(_ day: Date) {
        let normalizedDay = calendar.startOfDay(for: day)
        if qualifiedDates.contains(where: { calendar.isDate($0, inSameDayAs: normalizedDay) }) {
            return
        }
        qualifiedDates.append(normalizedDay)
        qualifiedDates.sort(by: >)
    }

    private func normalizeQualifiedDates(_ dates: [Date]) -> [Date] {
        var seen: Set<Date> = []
        var normalized: [Date] = []
        for date in dates {
            let day = calendar.startOfDay(for: date)
            if !seen.contains(day) {
                seen.insert(day)
                normalized.append(day)
            }
        }
        return normalized.sorted(by: >)
    }

    private func debugLogCounters(reason: String, condition: DailyQualificationCondition? = nil) {
        #if DEBUG
        let verseCount = verseIdsReadToday.count
        let seconds = Int(activeReadingSecondsToday.rounded())
        let reflections = reflectionsToday
        if let condition {
            print("[StreakManager] \(reason) | verses=\(verseCount) activeSeconds=\(seconds) reflections=\(reflections) qualifiedBy=\(condition.rawValue)")
        } else {
            print("[StreakManager] \(reason) | verses=\(verseCount) activeSeconds=\(seconds) reflections=\(reflections)")
        }
        #endif
    }
}
