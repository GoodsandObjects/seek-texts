import Foundation

struct StreakState: Codable, Equatable {
    var currentStreak: Int
    var longestStreak: Int
    var totalEngagedDays: Int
    var firstEngagedAt: Date?
    var lastEngagedAt: Date?
    var lastEngagedSource: StreakEngagementSource?
}
