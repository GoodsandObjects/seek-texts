import SwiftUI
import UIKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = PaywallViewModel()
    @State private var showSuccessState = false
    @State private var successPulse = false

    let context: PaywallContext?
    let streakDays: Int
    let customSubtitle: String?
    let onUnlock: () -> Void

    init(
        context: PaywallContext? = nil,
        streakDays: Int = 0,
        customSubtitle: String? = nil,
        onUnlock: @escaping () -> Void
    ) {
        self.context = context
        self.streakDays = streakDays
        self.customSubtitle = customSubtitle
        self.onUnlock = onUnlock
    }

    private var showStreakContext: Bool {
        streakDays >= 7
    }

    private var subtitle: String {
        if let customSubtitle, !customSubtitle.isEmpty {
            return customSubtitle
        }
        switch context {
        case .guidedStudyLimit:
            return "Unlimited Guided Study and richer reflections."
        case .noteLimit:
            return "You've reached your note limit."
        case .highlightLimit:
            return "Unlock unlimited highlights."
        case .shareLimit:
            return "Share without limits."
        case .none:
            return "Unlimited Guided Study and richer reflections."
        }
    }

    private var benefits: [String] {
        [
            "Unlimited notes and highlights",
            "Unlimited Guided Study",
            "Revisit your notes anytime"
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Text("Deepen your practice")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundColor(SeekTheme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(subtitle)
                            .font(.callout)
                            .foregroundColor(SeekTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Text("Join thousands building a daily reading habit.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(SeekTheme.textSecondary.opacity(0.82))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 28)

                    if showStreakContext {
                        Text("You've shown up consistently. Go deeper.")
                            .font(.subheadline)
                            .foregroundColor(SeekTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(benefits, id: \.self) { benefit in
                            benefitRow(benefit)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 12) {
                        pricingCard(for: .annual)
                        pricingCard(for: .monthly)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            VStack(spacing: 12) {
                Button {
                    Task {
                        let unlocked = await viewModel.purchaseSelectedPlan()
                        guard unlocked else { return }
                        await presentSuccessAndDismiss()
                    }
                } label: {
                    Text(viewModel.isLoading ? "Processing..." : "Unlock Premium")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SeekTheme.maroonAccent)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isLoading)

                Button("Not now") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(SeekTheme.textSecondary)
                .disabled(viewModel.isLoading)

                HStack {
                    Button("Restore") {
                        Task {
                            let restored = await viewModel.restorePurchases()
                            guard restored else { return }
                            await presentSuccessAndDismiss()
                        }
                    }

                    Text("·")
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.8))

                    Button("Terms") {
                        if let url = URL(string: "https://seek.app/terms") {
                            openURL(url)
                        }
                    }

                    Text("·")
                        .foregroundColor(SeekTheme.textSecondary.opacity(0.8))

                    Button("Privacy") {
                        if let url = URL(string: "https://seek.app/privacy") {
                            openURL(url)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(SeekTheme.textSecondary.opacity(0.8))
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .background(SeekTheme.creamBackground)
        }
        .overlay {
            if showSuccessState {
                successOverlay
            }
        }
        .themedScreenBackground()
        .alert("Purchase", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func pricingCard(for plan: SubscriptionPlan) -> some View {
        let isSelected = viewModel.selectedPlan == plan

        Button {
            viewModel.selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.title)
                        .font(.system(size: plan == .annual ? 19 : 17, weight: .semibold))
                        .foregroundColor(SeekTheme.textPrimary)
                }

                if plan == .annual {
                    Text("$59.99 per year")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(SeekTheme.textPrimary)

                    Text("Billed annually")
                        .font(.system(size: 13))
                        .foregroundColor(SeekTheme.textSecondary)
                } else {
                    Text("$7.99 per month")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(SeekTheme.textPrimary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? SeekTheme.maroonAccent.opacity(0.08) : SeekTheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? SeekTheme.maroonAccent : SeekTheme.textSecondary.opacity(0.22), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(14)
            .shadow(color: isSelected ? SeekTheme.cardShadow.opacity(1.6) : SeekTheme.cardShadow, radius: isSelected ? 10 : 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func benefitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SeekTheme.maroonAccent.opacity(0.6))
                .padding(.top, 4)
            Text(text)
                .font(.body)
                .foregroundColor(SeekTheme.textPrimary)
        }
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(SeekTheme.maroonAccent)
                    .scaleEffect(successPulse ? 1.06 : 0.92)
                    .animation(.easeInOut(duration: 0.5).repeatCount(2, autoreverses: true), value: successPulse)

                Text("Your journey continues.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(SeekTheme.textPrimary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(SeekTheme.creamBackground)
            .cornerRadius(16)
            .shadow(color: SeekTheme.cardShadow.opacity(1.4), radius: 10, x: 0, y: 4)
        }
        .transition(.opacity)
    }

    private func presentSuccessAndDismiss() async {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        feedback.impactOccurred()

        withAnimation(.easeInOut(duration: 0.2)) {
            showSuccessState = true
            successPulse = true
        }
        onUnlock()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        dismiss()
    }
}
