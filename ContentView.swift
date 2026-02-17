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
            }
            .tabItem {
                Label("Study", systemImage: "sparkles")
            }

            NavigationStack {
                JourneyScreen()
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
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
