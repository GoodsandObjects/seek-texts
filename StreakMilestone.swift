import Foundation

enum StreakMilestone: String, Codable, CaseIterable {
    case week
    case month
    case season
    case year

    var requiredStreak: Int {
        switch self {
        case .week:
            return 7
        case .month:
            return 30
        case .season:
            return 90
        case .year:
            return 365
        }
    }

    var acknowledgementText: String {
        switch self {
        case .week:
            return "Week completed."
        case .month:
            return "Month completed."
        case .season:
            return "Season completed."
        case .year:
            return "Year completed."
        }
    }

    static func matching(streak: Int) -> StreakMilestone? {
        allCases.first(where: { $0.requiredStreak == streak })
    }
}

struct StreakMilestoneAchievement: Codable, Equatable {
    let milestone: StreakMilestone
    let achievedAt: Date
}
