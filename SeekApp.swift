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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    await LibraryData.shared.bootstrapIfNeeded()
                    await RemoteDataService.shared.logBundleStartupVerification()
                    _ = await RemoteDataService.shared.prefetchTopFiveIfEligible()
                }
        }
    }
}
