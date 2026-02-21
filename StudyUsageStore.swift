import Foundation

enum StudyUsageStore {
    private static let key = "seek.study.usage.v1"

    static func load() -> StudyUsageState? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(StudyUsageState.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func save(_ state: StudyUsageState) {
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

