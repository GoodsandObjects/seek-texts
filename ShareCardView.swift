import SwiftUI

struct ShareCardPayload {
    let reference: String
    let verseText: String
    let scriptureName: String
    let caption: String?
    let isHighlighted: Bool
}

struct ShareCardView: View {
    let payload: ShareCardPayload

    private let offWhite = Color(red: 0.97, green: 0.95, blue: 0.92)

    var body: some View {
        ZStack {
            offWhite

            VStack(spacing: 28) {
                Spacer(minLength: 20)

                Text(payload.reference)
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .foregroundColor(SeekTheme.textSecondary)
                    .multilineTextAlignment(.center)

                Text(payload.verseText)
                    .font(.custom("Georgia", size: 52))
                    .foregroundColor(SeekTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(14)
                    .padding(.horizontal, 72)
                    .padding(.vertical, payload.isHighlighted ? 24 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(payload.isHighlighted ? Color(red: 1.0, green: 0.95, blue: 0.78) : .clear)
                    )

                if let caption = payload.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundColor(SeekTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .padding(.horizontal, 88)
                }

                Text(payload.scriptureName)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(SeekTheme.textSecondary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 72)

                Spacer()

                Text("Seek")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .tracking(1.5)
                    .foregroundColor(SeekTheme.textSecondary.opacity(0.75))
                    .padding(.bottom, 46)
            }
        }
        .frame(width: 1080, height: 1350)
        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
    }
}

#Preview {
    ShareCardView(
        payload: ShareCardPayload(
            reference: "Genesis 1:1",
            verseText: "In the beginning God created the heaven and the earth.",
            scriptureName: "Bible (KJV)",
            caption: "A quiet reminder to start again.",
            isHighlighted: false
        )
    )
    .padding()
    .background(Color.black.opacity(0.08))
}
