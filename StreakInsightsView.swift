import SwiftUI

struct StreakInsightsView: View {
    let longestStreak: Int
    let totalQualifiedDays: Int
    let qualifiedDates: [Date]
    let isPremium: Bool
    let onUnlockTap: () -> Void
    @State private var isExpanded = false

    private let calendar = Calendar.autoupdatingCurrent

    private var qualifiedDaySet: Set<Date> {
        Set(qualifiedDates.map { calendar.startOfDay(for: $0) })
    }

    private var last30Days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<30).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text("Insights")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(SeekTheme.textPrimary)

                    Spacer()

                    Text("Longest \(longestStreak) · \(totalQualifiedDays) total")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(SeekTheme.textSecondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.85))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Group {
                    if isPremium {
                        premiumContent
                    } else {
                        freePreview
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(SeekTheme.cardBackground.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(SeekTheme.textSecondary.opacity(0.08), lineWidth: 1)
                )
                .cornerRadius(15)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isExpanded)
    }

    private var premiumContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                compactMetric(title: "Longest Streak", value: "\(longestStreak)")
                compactMetric(title: "Total Qualified Days", value: "\(totalQualifiedDays)")
            }

            thirtyDayTimeline(isBlurred: false)
        }
    }

    private var freePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                compactMetric(title: "Longest Streak", value: "\(longestStreak)")
                compactMetric(title: "Total Qualified Days", value: "\(totalQualifiedDays)")
            }

            thirtyDayTimeline(isBlurred: true)

            Text("Unlock Insights to view your consistency.")
                .font(.system(size: 13))
                .foregroundColor(SeekTheme.textSecondary)

            Button(action: onUnlockTap) {
                Text("Unlock Insights")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SeekTheme.maroonAccent)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SeekTheme.textSecondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SeekTheme.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thirtyDayTimeline(isBlurred: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(last30Days, id: \.self) { day in
                Circle()
                    .fill(
                        qualifiedDaySet.contains(calendar.startOfDay(for: day))
                            ? SeekTheme.maroonAccent.opacity(0.9)
                            : SeekTheme.textSecondary.opacity(0.2)
                    )
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blur(radius: isBlurred ? 1.8 : 0)
    }
}

#Preview {
    StreakInsightsView(
        longestStreak: 21,
        totalQualifiedDays: 47,
        qualifiedDates: [],
        isPremium: true,
        onUnlockTap: {}
    )
    .padding()
    .background(SeekTheme.creamBackground)
}
