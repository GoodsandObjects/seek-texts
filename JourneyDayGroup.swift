import Foundation

struct JourneyDaySection: Identifiable {
    let day: Date
    var items: [JourneyFeedItem]

    var id: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: day)
    }
}

