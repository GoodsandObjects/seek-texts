import SwiftUI

struct JourneyDayHeaderRow: View {
    let title: String
    let summary: String
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SeekTheme.textPrimary)

                Spacer(minLength: 8)

                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(SeekTheme.textSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SeekTheme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

