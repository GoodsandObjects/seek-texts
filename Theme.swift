import SwiftUI

// MARK: - Seek App Theme

struct SeekTheme {

    // MARK: - Colors

    static let creamBackground = Color(red: 0.97, green: 0.95, blue: 0.92)
    static let maroonAccent = Color(red: 0.75, green: 0.38, blue: 0.28)
    static let textPrimary = Color(red: 0.12, green: 0.10, blue: 0.08)
    static let textSecondary = Color(red: 0.55, green: 0.50, blue: 0.45)
    static let cardBackground = Color.white
    static let cardShadow = Color.black.opacity(0.03)

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
            .background(SeekTheme.creamBackground.ignoresSafeArea())
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
                .fill(SeekTheme.maroonAccent.opacity(0.08))
                .frame(width: size, height: size)

            Image(systemName: systemName)
                .font(.system(size: iconFontSize, weight: .medium))
                .foregroundColor(SeekTheme.maroonAccent)
        }
    }
}

// MARK: - Themed Chevron

struct ThemedChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(SeekTheme.maroonAccent.opacity(0.4))
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
                    .foregroundColor(SeekTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(SeekTheme.textSecondary)
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
