import SwiftUI
import UIKit

struct GuidedStudyShareCardView: View {
    let reference: String
    let excerpt: String?
    let reflection: String?

    var body: some View {
        ZStack {
            SeekTheme.creamBackground

            VStack(spacing: 0) {
                Spacer().frame(height: 90)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Guided Study")
                        .font(.system(size: 22, weight: .medium, design: .default))
                        .tracking(1.8)
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.86))

                    Text(reference)
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundColor(SeekTheme.textPrimary)
                        .padding(.top, 22)

                    if let excerpt, !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.system(size: 42, weight: .regular, design: .serif))
                            .foregroundColor(SeekTheme.textPrimary)
                            .lineSpacing(12)
                            .lineLimit(5)
                            .padding(.top, 36)
                    }

                    if let reflection, !reflection.isEmpty {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(SeekTheme.textSecondary.opacity(0.22))
                            .frame(height: 1)
                            .padding(.top, 36)

                        Text("Reflection")
                            .font(.system(size: 21, weight: .medium, design: .default))
                            .tracking(1.2)
                            .foregroundColor(SeekTheme.textSecondary.opacity(0.9))
                            .padding(.top, 24)

                        Text(reflection)
                            .font(.system(size: 31, weight: .regular, design: .serif))
                            .foregroundColor(SeekTheme.textSecondary.opacity(0.97))
                            .lineSpacing(10)
                            .lineLimit(6)
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 96)

                Spacer(minLength: 76)

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
    GuidedStudyShareCardView(
        reference: "1 Samuel 1",
        excerpt: "The Lord remembered her. In due time she conceived and bore a son.",
        reflection: "I want to carry patience with hope this week."
    )
    .padding()
    .background(Color.black.opacity(0.08))
}
