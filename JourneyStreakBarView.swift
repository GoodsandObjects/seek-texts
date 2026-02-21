import SwiftUI

private struct StreakBarStyle {
    enum Tier {
        case tier0
        case tier1
        case tier2
        case tier3
    }

    let tier: Tier
    let filledStyle: AnyShapeStyle
    let unfilledColor: Color
    let nextSegmentOutlineColor: Color
    let tier3OverlayStroke: Color
    let glowColor: Color
    let glowRadius: CGFloat
    let glowYOffset: CGFloat

    static func make(currentStreak: Int, isQualifiedToday: Bool, accent: Color, neutral: Color) -> StreakBarStyle {
        let intensity = isQualifiedToday ? 1.0 : 0.92
        let resolvedTier: Tier

        switch currentStreak {
        case ..<7:
            resolvedTier = .tier0
        case 7..<30:
            resolvedTier = .tier1
        case 30..<90:
            resolvedTier = .tier2
        default:
            resolvedTier = .tier3
        }

        let filled: AnyShapeStyle
        switch resolvedTier {
        case .tier0:
            filled = AnyShapeStyle(accent.opacity(0.88 * intensity))
        case .tier1:
            filled = AnyShapeStyle(accent.opacity(1.0 * intensity))
        case .tier2:
            filled = AnyShapeStyle(
                LinearGradient(
                    colors: [
                        accent.opacity(1.0 * intensity),
                        accent.opacity(0.93 * intensity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .tier3:
            filled = AnyShapeStyle(
                LinearGradient(
                    colors: [
                        accent.opacity(1.0 * intensity),
                        accent.opacity(0.92 * intensity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return StreakBarStyle(
            tier: resolvedTier,
            filledStyle: filled,
            unfilledColor: neutral.opacity(0.14),
            nextSegmentOutlineColor: accent.opacity(0.24),
            tier3OverlayStroke: accent.opacity(0.2),
            glowColor: resolvedTier == .tier3 ? accent.opacity(0.1) : .clear,
            glowRadius: resolvedTier == .tier3 ? 1.8 : 0,
            glowYOffset: resolvedTier == .tier3 ? 0.5 : 0
        )
    }
}

struct JourneyStreakBarView: View {
    let currentStreak: Int
    let isQualifiedToday: Bool
    let milestoneCopy: String?
    var onShareTap: (() -> Void)? = nil

    private let segmentCount = 7

    private var filledSegments: Int {
        min(max(currentStreak, 0), segmentCount)
    }

    private var nextSegmentIndex: Int? {
        guard !isQualifiedToday else { return nil }
        guard filledSegments < segmentCount else { return nil }
        return filledSegments
    }

    private var baseAccent: Color {
        SeekTheme.maroonAccent
    }

    private var milestoneLineText: String {
        milestoneCopy ?? " "
    }

    private var barStyle: StreakBarStyle {
        StreakBarStyle.make(
            currentStreak: currentStreak,
            isQualifiedToday: isQualifiedToday,
            accent: baseAccent,
            neutral: SeekTheme.textSecondary
        )
    }

    // Journey streak bar is intentional. Do not remove. Reader remains streak-free.
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Streak")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(0.25)
                    .foregroundColor(SeekTheme.textSecondary)

                Spacer()

                Text("\(currentStreak) \(currentStreak == 1 ? "day" : "days")")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(SeekTheme.textSecondary.opacity(0.9))
                    .monospacedDigit()

                if let onShareTap {
                    Button(action: onShareTap) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(SeekTheme.textSecondary.opacity(0.78))
                            .padding(.leading, 8)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    let isFilled = index < filledSegments
                    Capsule()
                        .fill(isFilled ? barStyle.filledStyle : AnyShapeStyle(barStyle.unfilledColor))
                        .overlay {
                            if nextSegmentIndex == index {
                                Capsule()
                                    .stroke(barStyle.nextSegmentOutlineColor, lineWidth: 1)
                            }
                            if isFilled, barStyle.tier == .tier3 {
                                Capsule()
                                    .stroke(barStyle.tier3OverlayStroke, lineWidth: 0.8)
                            }
                        }
                        .shadow(
                            color: isFilled ? barStyle.glowColor : .clear,
                            radius: barStyle.glowRadius,
                            x: 0,
                            y: barStyle.glowYOffset
                        )
                        .frame(height: 10)
                }
            }

            Text(milestoneLineText)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(SeekTheme.textSecondary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 14, alignment: .topLeading)
                .opacity(milestoneCopy == nil ? 0 : 1)
                .accessibilityHidden(milestoneCopy == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(SeekTheme.cardBackground)
        .cornerRadius(15)
        .shadow(color: SeekTheme.cardShadow.opacity(0.75), radius: 4, x: 0, y: 1)
    }
}

#Preview {
    VStack(spacing: 16) {
        JourneyStreakBarView(currentStreak: 0, isQualifiedToday: false, milestoneCopy: nil)
        JourneyStreakBarView(currentStreak: 7, isQualifiedToday: true, milestoneCopy: "Week completed.")
        JourneyStreakBarView(currentStreak: 30, isQualifiedToday: true, milestoneCopy: "Month completed.")
        JourneyStreakBarView(currentStreak: 90, isQualifiedToday: true, milestoneCopy: "Season completed.")
    }
    .padding()
    .background(SeekTheme.creamBackground)
}
