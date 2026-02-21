//
//  ContentView.swift
//  Seek
//
//  Root content view with tab navigation.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            // Library tab has its own NavigationStack with search
            LibraryScreenNew()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }

            NavigationStack {
                StudyHomeScreen()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem {
                Label("Study", systemImage: "sparkles")
            }

            NavigationStack {
                JourneyScreen()
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(route)
                    }
            }
            .tabItem {
                Label("Journey", systemImage: "heart.fill")
            }

            NavigationStack {
                SettingsScreen()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(SeekTheme.maroonAccent)
        .fullScreenCover(isPresented: $appState.isPaywallPresented, onDismiss: {
            appState.dismissPaywall()
        }) {
            PaywallView(
                context: appState.paywallContext,
                streakDays: StreakStore().load()?.currentStreak ?? 0
            ) {
                appState.handlePaywallUnlocked()
            }
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .reader(let destination):
            RoutedReaderDestinationView(destination: destination)
                .environmentObject(appState)
        case .guidedStudy(let conversationId):
            ResumeConversationView(conversationId: conversationId)
                .environmentObject(appState)
        case .error(let title, let message):
            RouteLoadFailureView(title: title, message: message)
        }
    }
}

struct RoutedReaderDestinationView: View {
    let destination: ReaderDestination

    var body: some View {
        if destination.scriptureId.isEmpty || destination.bookId.isEmpty || destination.chapter < 1 {
            RouteLoadFailureView(
                title: "Unable to Open Session",
                message: "This session can't be opened. It may have been created with an older version."
            )
        } else {
            ReaderScreen(
                chapterRef: ChapterRef(
                    scriptureId: destination.scriptureId,
                    bookId: destination.bookId,
                    chapterNumber: destination.chapter,
                    bookName: destination.bookName
                ),
                initialVerseNumber: destination.verseStart
            )
        }
    }
}

struct RouteLoadFailureView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(SeekTheme.maroonAccent)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SeekTheme.textPrimary)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(SeekTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button("Back") {
                dismiss()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(SeekTheme.maroonAccent)
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedScreenBackground()
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
