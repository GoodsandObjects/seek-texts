import Foundation

final class StudyUsageTracker {
    static let shared = StudyUsageTracker()

    private let calendar: Calendar
    private let freeDailyLimit = 3

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func canSendMessage(isPremium: Bool) -> Bool {
        if isPremium {
            return true
        }
        return normalizedState(for: calendar.startOfDay(for: Date())).messagesUsedToday < freeDailyLimit
    }

    func incrementAfterSend() {
        let today = calendar.startOfDay(for: Date())
        var state = normalizedState(for: today)
        state.messagesUsedToday += 1
        StudyUsageStore.save(state)
    }

    func resetForNewDayIfNeeded() {
        let today = calendar.startOfDay(for: Date())
        let state = normalizedState(for: today)
        StudyUsageStore.save(state)
    }

    func currentState() -> StudyUsageState {
        let today = calendar.startOfDay(for: Date())
        return normalizedState(for: today)
    }

    func canSendMessageToday() -> Bool {
        canSendMessage(isPremium: FeatureGate.canUseUnlimitedStudy())
    }

    func incrementIfAllowed() -> Bool {
        let allowed = canSendMessage(isPremium: FeatureGate.canUseUnlimitedStudy())
        if allowed, !FeatureGate.canUseUnlimitedStudy() {
            incrementAfterSend()
        }
        return allowed
    }

    func reset() {
        StudyUsageStore.reset()
    }

    private func normalizedState(for today: Date) -> StudyUsageState {
        guard var state = StudyUsageStore.load() else {
            return StudyUsageState(day: today, messagesUsedToday: 0)
        }

        let savedDay = calendar.startOfDay(for: state.day)
        if savedDay != today {
            state.day = today
            state.messagesUsedToday = 0
        }

        return state
    }
}
