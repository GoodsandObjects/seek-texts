import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var libraryData = LibraryData.shared
    @State private var showClearCacheConfirmation = false
    @State private var cacheSize: String = "Calculating..."
    #if DEBUG
    @State private var isLoadingDataStatus = false
    @State private var isPrefetchingTopFive = false
    @State private var dataStatusReport: RemoteDataService.DataStatusReport?
    @State private var prefetchSummary: String = ""
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Account Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Account")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SeekTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        HStack {
                            Text("Seek Guided")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(SeekTheme.textPrimary)

                            Spacer()

                            Text(appState.effectivelyGuided ? "Active" : "Free")
                                .font(.system(size: 15))
                                .foregroundColor(appState.effectivelyGuided ? SeekTheme.maroonAccent : SeekTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    appState.effectivelyGuided ?
                                    SeekTheme.maroonAccent.opacity(0.1) :
                                    SeekTheme.creamBackground
                                )
                                .cornerRadius(8)
                        }
                        .padding(16)
                    }
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)
                    .shadow(color: SeekTheme.cardShadow, radius: 6, x: 0, y: 2)
                }

                // Stats Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Journey")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SeekTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        SettingsStatRow(
                            label: "Highlights",
                            value: "\(appState.highlights.count)",
                            limit: appState.effectivelyGuided ? nil : AppState.maxHighlightsFree
                        )

                        Divider()
                            .padding(.leading, 16)

                        SettingsStatRow(
                            label: "Notes",
                            value: "\(appState.notes.count)",
                            limit: appState.effectivelyGuided ? nil : AppState.maxNotesFree
                        )

                        Divider()
                            .padding(.leading, 16)

                        SettingsStatRow(
                            label: "Guided Sessions",
                            value: "\(appState.guidedSessions.count)",
                            limit: nil
                        )
                    }
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)
                    .shadow(color: SeekTheme.cardShadow, radius: 6, x: 0, y: 2)
                }

                // Storage Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SeekTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cached Texts")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(SeekTheme.textPrimary)

                                Text("Texts you've read are saved for offline access")
                                    .font(.system(size: 13))
                                    .foregroundColor(SeekTheme.textSecondary)
                            }

                            Spacer()

                            Text(cacheSize)
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)
                        }
                        .padding(16)

                        Divider()
                            .padding(.leading, 16)

                        Button {
                            showClearCacheConfirmation = true
                        } label: {
                            HStack {
                                Text("Clear Cache")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(SeekTheme.maroonAccent)

                                Spacer()

                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                    .foregroundColor(SeekTheme.maroonAccent)
                            }
                            .padding(16)
                        }
                    }
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)
                    .shadow(color: SeekTheme.cardShadow, radius: 6, x: 0, y: 2)
                }

                // About Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("About")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SeekTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        HStack {
                            Text("Version")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(SeekTheme.textPrimary)

                            Spacer()

                            Text(appVersion)
                                .font(.system(size: 15))
                                .foregroundColor(SeekTheme.textSecondary)
                        }
                        .padding(16)
                    }
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)
                    .shadow(color: SeekTheme.cardShadow, radius: 6, x: 0, y: 2)
                }

                #if DEBUG
                // Developer Section (only in debug builds)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Developer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SeekTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        Toggle(isOn: Binding(
                            get: { appState.guidedSandboxMode },
                            set: { appState.setSandboxMode($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sandbox Mode")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(SeekTheme.textPrimary)

                                Text("Bypass paywall for testing")
                                    .font(.system(size: 13))
                                    .foregroundColor(SeekTheme.textSecondary)
                            }
                        }
                        .tint(SeekTheme.maroonAccent)
                        .padding(16)

                        Divider()
                            .padding(.leading, 16)

                        Toggle(isOn: Binding(
                            get: { RemoteConfig.useMockGuidedStudyProvider },
                            set: { RemoteConfig.useMockGuidedStudyProvider = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Guided Study Mock Provider")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(SeekTheme.textPrimary)

                                Text("Use local mock responses instead of live proxy")
                                    .font(.system(size: 13))
                                    .foregroundColor(SeekTheme.textSecondary)
                            }
                        }
                        .tint(SeekTheme.maroonAccent)
                        .padding(16)

                        Divider()
                            .padding(.leading, 16)

                        HStack {
                            Text("Guided Study Proxy")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(SeekTheme.textPrimary)

                            Spacer()

                            Text(RemoteConfig.hasConfiguredOpenAIProxyBaseURL ? "Configured" : "Not configured")
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)
                        }
                        .padding(16)

                        Divider()
                            .padding(.leading, 16)

                        HStack {
                            Text("Data Source")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(SeekTheme.textPrimary)

                            Spacer()

                            Text(libraryData.loadSource.isEmpty ? "Remote" : libraryData.loadSource)
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)
                        }
                        .padding(16)

                        Divider()
                            .padding(.leading, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Data Status")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(SeekTheme.textPrimary)
                                Spacer()
                                if isLoadingDataStatus {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }

                            if let report = dataStatusReport {
                                Text("index.json source: \(report.sourceSummary)")
                                    .font(.system(size: 13))
                                    .foregroundColor(SeekTheme.textSecondary)

                                Text("Locations: bundle \(report.hasBundleIndex ? "yes" : "no") • cache \(report.hasCacheIndex ? "yes" : "no") • remote \(report.hasRemoteIndex ? "yes" : "no")")
                                    .font(.system(size: 12))
                                    .foregroundColor(SeekTheme.textSecondary)

                                ForEach(report.scriptureStatuses) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(SeekTheme.textPrimary)
                                        Text("books \(item.totalBooks), chapters \(item.totalChapters), sample \(item.sampleChapterReference): \(item.sampleChapterSuccess ? "ok" : "failed")")
                                            .font(.system(size: 12))
                                            .foregroundColor(SeekTheme.textSecondary)
                                    }
                                }
                            } else {
                                Text("No status loaded yet.")
                                    .font(.system(size: 12))
                                    .foregroundColor(SeekTheme.textSecondary)
                            }

                            Text("Cache size: \(cacheSize)")
                                .font(.system(size: 12))
                                .foregroundColor(SeekTheme.textSecondary)

                            HStack(spacing: 10) {
                                Button {
                                    refreshDataStatus()
                                } label: {
                                    Text("Refresh Data Status")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(SeekTheme.maroonAccent)
                                        .cornerRadius(8)
                                }
                                .disabled(isLoadingDataStatus || isPrefetchingTopFive)

                                Button {
                                    prefetchTopFiveNow()
                                } label: {
                                    Text(isPrefetchingTopFive ? "Prefetching..." : "Prefetch top-5 now")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(SeekTheme.maroonAccent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(SeekTheme.maroonAccent, lineWidth: 1)
                                        )
                                }
                                .disabled(isLoadingDataStatus || isPrefetchingTopFive)
                            }

                            if !prefetchSummary.isEmpty {
                                Text(prefetchSummary)
                                    .font(.system(size: 12))
                                    .foregroundColor(SeekTheme.textSecondary)
                            }
                        }
                        .padding(16)
                    }
                    .background(SeekTheme.cardBackground)
                    .cornerRadius(14)
                    .shadow(color: SeekTheme.cardShadow, radius: 6, x: 0, y: 2)
                }
                #endif
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .themedScreenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(SeekTheme.creamBackground, for: .navigationBar)
        .onAppear {
            updateCacheSize()
            #if DEBUG
            refreshDataStatus()
            #endif
        }
        .confirmationDialog("Clear Cache", isPresented: $showClearCacheConfirmation) {
            Button("Clear Cache", role: .destructive) {
                clearCache()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all cached texts. You'll need an internet connection to read texts again.")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func updateCacheSize() {
        Task { @MainActor in
            let size = RemoteDataService.shared.getCacheSize()
            cacheSize = formatBytes(size)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    private func clearCache() {
        RemoteDataService.shared.clearAllCaches()
        updateCacheSize()
        #if DEBUG
        refreshDataStatus()
        #endif
    }

    #if DEBUG
    private func refreshDataStatus() {
        guard !isLoadingDataStatus else { return }
        isLoadingDataStatus = true
        Task { @MainActor in
            dataStatusReport = await RemoteDataService.shared.topFiveDataStatusReport()
            updateCacheSize()
            isLoadingDataStatus = false
        }
    }

    private func prefetchTopFiveNow() {
        guard !isPrefetchingTopFive else { return }
        isPrefetchingTopFive = true
        prefetchSummary = ""
        Task { @MainActor in
            let result = await RemoteDataService.shared.prefetchTopFiveNow()
            prefetchSummary = "Prefetch complete: \(result.succeededChapters)/\(result.attemptedChapters) chapters cached, \(result.failedChapters) failed."
            isPrefetchingTopFive = false
            refreshDataStatus()
        }
    }
    #endif
}

// MARK: - Settings Stat Row

private struct SettingsStatRow: View {
    let label: String
    let value: String
    let limit: Int?

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(SeekTheme.textPrimary)

            Spacer()

            if let limit = limit {
                Text("\(value) / \(limit)")
                    .font(.system(size: 15))
                    .foregroundColor(SeekTheme.textSecondary)
            } else {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundColor(SeekTheme.textSecondary)
            }
        }
        .padding(16)
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
            .environmentObject(AppState())
    }
}
