import SwiftUI
import UIKit

struct VerseShareCardView: View {
    let verseText: String
    let referenceText: String
    let sourceText: String?

    var body: some View {
        ZStack {
            SeekTheme.creamBackground

            VStack(spacing: 0) {
                Spacer().frame(height: 110)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Verse")
                        .font(.system(size: 22, weight: .medium, design: .default))
                        .tracking(1.8)
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.86))

                    Text(referenceText)
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundColor(SeekTheme.textPrimary)
                        .padding(.top, 20)

                    if let sourceText, !sourceText.isEmpty {
                        Text(sourceText)
                            .font(.system(size: 22, weight: .regular, design: .default))
                            .foregroundColor(SeekTheme.textSecondary.opacity(0.88))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.top, 12)
                    }

                    Text(verseText)
                        .font(.system(size: 48, weight: .regular, design: .serif))
                        .foregroundColor(SeekTheme.textPrimary)
                        .lineSpacing(12)
                        .lineLimit(10)
                        .truncationMode(.tail)
                        .padding(.top, 36)
                }
                .padding(.horizontal, 96)

                Spacer(minLength: 80)

                wordmark
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 56)
            }
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .shadow(color: Color.black.opacity(0.03), radius: 18, x: 0, y: 5)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
            )
        }
        .frame(width: 1080, height: 1350)
        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
    }

    @ViewBuilder
    private var wordmark: some View {
        if let image = UIImage(named: "SeekWordmark") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .foregroundColor(SeekTheme.textSecondary.opacity(0.75))
        } else {
            Text("SEEK")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .tracking(3.2)
                .foregroundColor(SeekTheme.textSecondary.opacity(0.75))
        }
    }
}

#Preview {
    VerseShareCardView(
        verseText: "In the beginning God created the heaven and the earth.",
        referenceText: "Genesis 1:1",
        sourceText: "Bible (KJV)"
    )
    .padding()
    .background(Color.black.opacity(0.08))
}
