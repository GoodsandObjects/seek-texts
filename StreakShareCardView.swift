import SwiftUI
import UIKit

private struct StreakShareBarStyle {
    enum Tier {
        case tier0
        case tier1
        case tier2
        case tier3
    }

    let tier: Tier
    let filledStyle: AnyShapeStyle
    let unfilledColor: Color
    let tier3OverlayStroke: Color
    let glowColor: Color
    let glowRadius: CGFloat
    let glowYOffset: CGFloat

    static func make(currentStreak: Int, isQualifiedToday: Bool, accent: Color, neutral: Color) -> StreakShareBarStyle {
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

        return StreakShareBarStyle(
            tier: resolvedTier,
            filledStyle: filled,
            unfilledColor: neutral.opacity(0.14),
            tier3OverlayStroke: accent.opacity(0.2),
            glowColor: resolvedTier == .tier3 ? accent.opacity(0.1) : .clear,
            glowRadius: resolvedTier == .tier3 ? 1.8 : 0,
            glowYOffset: resolvedTier == .tier3 ? 0.5 : 0
        )
    }
}

struct StreakShareCardView: View {
    let currentStreak: Int
    let milestoneCopy: String?
    let isQualifiedToday: Bool

    private let segmentCount = 7

    private var filledSegments: Int {
        min(max(currentStreak, 0), segmentCount)
    }

    private var baseAccent: Color {
        SeekTheme.maroonAccent
    }

    private var barStyle: StreakShareBarStyle {
        StreakShareBarStyle.make(
            currentStreak: currentStreak,
            isQualifiedToday: isQualifiedToday,
            accent: baseAccent,
            neutral: SeekTheme.textSecondary
        )
    }

    private var streakLine: String {
        currentStreak == 1 ? "1 day streak" : "\(currentStreak) days"
    }

    var body: some View {
        ZStack {
            SeekTheme.creamBackground

            VStack(spacing: 0) {
                Spacer().frame(height: 140)

                Text("My Journey")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundColor(SeekTheme.textSecondary)

                Text(streakLine)
                    .font(.system(size: 70, weight: .medium, design: .serif))
                    .foregroundColor(SeekTheme.textPrimary)
                    .padding(.top, 22)

                HStack(spacing: 14) {
                    ForEach(0..<segmentCount, id: \.self) { index in
                        Capsule()
                            .fill(index < filledSegments ? barStyle.filledStyle : AnyShapeStyle(barStyle.unfilledColor))
                            .overlay {
                                if index < filledSegments, barStyle.tier == .tier3 {
                                    Capsule()
                                        .stroke(barStyle.tier3OverlayStroke, lineWidth: 1)
                                }
                            }
                            .shadow(
                                color: index < filledSegments ? barStyle.glowColor : .clear,
                                radius: barStyle.glowRadius,
                                x: 0,
                                y: barStyle.glowYOffset
                            )
                            .frame(height: 22)
                    }
                }
                .padding(.horizontal, 132)
                .padding(.top, 44)

                Spacer()

                if let uiImage = UIImage(named: "SeekWordmark") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 34)
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.75))
                        .padding(.bottom, 56)
                } else {
                    Text("SEEK")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .tracking(3)
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.75))
                        .padding(.bottom, 54)
                }
            }
        }
        .frame(width: 1080, height: 1350)
        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
    }
}

#Preview {
    StreakShareCardView(
        currentStreak: 34,
        milestoneCopy: "Month completed.",
        isQualifiedToday: true
    )
    .padding()
    .background(Color.black.opacity(0.08))
}
