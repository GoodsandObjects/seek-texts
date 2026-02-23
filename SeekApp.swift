//
//  SeekApp.swift
//  Seek
//
//  Main app entry point.
//

import SwiftUI

@main
struct SeekApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appSettings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appSettings.appearanceMode.colorScheme)
                .task {
                    await StoreManager.shared.configure()
                    await LibraryData.shared.bootstrapIfNeeded()
                    await RemoteDataService.shared.logBundleStartupVerification()
                    _ = await RemoteDataService.shared.prefetchTopFiveIfEligible()
                }
        }
    }
}
