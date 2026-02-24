import SwiftUI

// SEEK BRAND SYSTEM
// All UI colors must route through Brand tokens.
// No hardcoded colors in views.

enum Brand {
    // Temporary placeholder accent until final brand palette is locked.
    static let primaryAccent = Color(red: 0.75, green: 0.38, blue: 0.28)
    static let primaryAccentMuted = primaryAccent.opacity(0.12)
    static let onAccentText = Color(uiColor: .white)
    static let backgroundPrimary = Color(.systemBackground)
    static let backgroundGrouped = Color(.systemGroupedBackground)
    static let surfacePrimary = Color(.secondarySystemBackground)
    static let surfaceSecondary = Color(.tertiarySystemBackground)
    static let borderSubtle = Color(.separator)
    static let destructive = Color(uiColor: .systemRed)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
}

// MARK: - Seek App Theme

struct SeekTheme {

    // MARK: - Colors

    static let creamBackground = Brand.backgroundPrimary
    static let screenBackground = Brand.backgroundGrouped
    static let maroonAccent = Brand.primaryAccent
    static let textPrimary = Brand.textPrimary
    static let textSecondary = Brand.textSecondary
    static let onAccentText = Brand.onAccentText
    static let onAccentTextMuted = Brand.onAccentText.opacity(0.8)
    static let cardBackground = Brand.surfacePrimary
    static let cardShadow = Color.primary.opacity(0.08)
    static let elevatedShadowWeak = Color.primary.opacity(0.03)
    static let elevatedShadowSubtle = Color.primary.opacity(0.02)
    static let overlayShadow = Color.primary.opacity(0.15)

    // MARK: - Dimensions

    static let cardCornerRadius: CGFloat = 16
    static let iconBackgroundCornerRadius: CGFloat = 14
    static let iconSize: CGFloat = 52
    static let iconFontSize: CGFloat = 20
    static let cardHorizontalPadding: CGFloat = 16
    static let cardVerticalPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 12
    static let screenHorizontalPadding: CGFloat = 20
}

// MARK: - Themed Card Modifier

struct ThemedCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(SeekTheme.cardBackground)
            .cornerRadius(SeekTheme.cardCornerRadius)
            .shadow(color: SeekTheme.cardShadow, radius: 8, x: 0, y: 2)
    }
}

extension View {
    func themedCard() -> some View {
        modifier(ThemedCardStyle())
    }
}

// MARK: - Themed Screen Background Modifier

struct ThemedScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(SeekTheme.screenBackground.ignoresSafeArea())
    }
}

extension View {
    func themedScreenBackground() -> some View {
        modifier(ThemedScreenBackground())
    }
}

// MARK: - Themed Icon View

struct ThemedIconView: View {
    let systemName: String
    var size: CGFloat = SeekTheme.iconSize
    var iconFontSize: CGFloat = SeekTheme.iconFontSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SeekTheme.iconBackgroundCornerRadius)
                .fill(Brand.primaryAccentMuted)
                .frame(width: size, height: size)

            Image(systemName: systemName)
                .font(.system(size: iconFontSize, weight: .medium))
                .foregroundColor(Brand.primaryAccent.opacity(0.85))
        }
    }
}

// MARK: - Themed Chevron

struct ThemedChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Brand.textSecondary.opacity(0.6))
    }
}

// MARK: - Simple Themed Row

struct SimpleThemedRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ThemedIconView(systemName: icon)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Brand.textPrimary)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Brand.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            ThemedChevron()
        }
        .padding(.horizontal, SeekTheme.cardHorizontalPadding)
        .padding(.vertical, SeekTheme.cardVerticalPadding)
        .themedCard()
    }
}
