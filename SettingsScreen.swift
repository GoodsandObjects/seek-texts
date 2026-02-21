import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var libraryData = LibraryData.shared
    @StateObject private var studyStore = StudyStore.shared
    @State private var showClearCacheConfirmation = false
    @State private var cacheSize: String = "Calculating..."
    #if DEBUG
    @State private var isLoadingDataStatus = false
    @State private var isPrefetchingTopFive = false
    @State private var dataStatusReport: RemoteDataService.DataStatusReport?
    @State private var prefetchSummary: String = ""
    @State private var streakState: StreakState?
    @State private var entitlementState: SubscriptionState = SubscriptionStore.load()
    @State private var studyUsageState: StudyUsageState = StudyUsageTracker.shared.currentState()
    @State private var proxyDebugLog: String = ""
    @State private var isProxyHealthCheckRunning = false
    @State private var isProxyRequestTestRunning = false
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
                            value: "\(studyStore.conversations.count)",
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Subscription Status")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(SeekTheme.textPrimary)

                            debugStatusRow(label: "Premium", value: entitlementState.isPremium ? "Yes" : "No")
                            debugStatusRow(label: "Source", value: debugFormattedSource(entitlementState.source))
                            debugStatusRow(label: "Expiration", value: debugFormattedEntitlementDate(entitlementState.expirationDate))

                            Button {
                                refreshEntitlementStatus()
                            } label: {
                                Text("Refresh")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(SeekTheme.maroonAccent)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(16)

                        Divider()
                            .padding(.leading, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Streak Status")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(SeekTheme.textPrimary)

                            Text("Current Streak: \(streakState?.currentStreak ?? 0)")
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)

                            Text("Longest Streak: \(streakState?.longestStreak ?? 0)")
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)

                            Text("Last Engaged Day: \(debugFormattedEngagedDay(streakState?.lastEngagedAt))")
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)

                            Text("First Engaged Day: \(debugFormattedEngagedDay(streakState?.firstEngagedAt))")
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)

                            Text("Last Engaged Source: \(streakState?.lastEngagedSource?.rawValue ?? "none")")
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)

                            HStack(spacing: 10) {
                                Button {
                                    let store = StreakStore()
                                    store.reset()
                                    refreshStreakStatus()
                                } label: {
                                    Text("Reset Streak")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(SeekTheme.maroonAccent)
                                        .cornerRadius(8)
                                }

                                Button {
                                    simulateLastEngagedDaysAgo(1)
                                } label: {
                                    Text("Simulate Yesterday")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(SeekTheme.maroonAccent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(SeekTheme.maroonAccent, lineWidth: 1)
                                        )
                                }

                                Button {
                                    simulateLastEngagedDaysAgo(3)
                                } label: {
                                    Text("Simulate 3 Days Ago")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(SeekTheme.maroonAccent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(SeekTheme.maroonAccent, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(16)

                        Divider()
                            .padding(.leading, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Guided Study Usage")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(SeekTheme.textPrimary)

                            debugStatusRow(label: "Messages Used Today", value: "\(studyUsageState.messagesUsedToday)")
                            debugStatusRow(label: "Day", value: debugFormattedEngagedDay(studyUsageState.day))
                            debugStatusRow(label: "Notes Count", value: "\(UsageLimitManager.shared.totalNotesCount())")
                            debugStatusRow(label: "Highlights Count", value: "\(UsageLimitManager.shared.totalHighlightsCount())")

                            HStack(spacing: 10) {
                                Button {
                                    StudyUsageTracker.shared.reset()
                                    refreshStudyUsageStatus()
                                } label: {
                                    Text("Reset Usage")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(SeekTheme.maroonAccent)
                                        .cornerRadius(8)
                                }

                                Button {
                                    refreshStudyUsageStatus()
                                } label: {
                                    Text("Refresh")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(SeekTheme.maroonAccent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(SeekTheme.maroonAccent, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(16)

                        Divider()
                            .padding(.leading, 16)

                        Toggle(isOn: Binding(
                            get: { appState.guidedSandboxMode },
                            set: {
                                appState.setSandboxMode($0)
                                refreshEntitlementStatus()
                                refreshStudyUsageStatus()
                            }
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

                            Text(RemoteConfig.hasConfiguredGuidedStudyProxyBaseURL ? "Configured" : "Not configured")
                                .font(.system(size: 13))
                                .foregroundColor(SeekTheme.textSecondary)
                        }
                        .padding(16)

                        #if DEBUG
                        Divider()
                            .padding(.leading, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(RemoteConfig.guidedStudyProxyBaseURL)
                                .font(.system(size: 12))
                                .foregroundColor(SeekTheme.textSecondary)
                                .textSelection(.enabled)

                            HStack(spacing: 10) {
                                Button {
                                    runProxyHealthCheck()
                                } label: {
                                    Text(isProxyHealthCheckRunning ? "Testing /health..." : "Test /health")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(SeekTheme.maroonAccent)
                                        .cornerRadius(8)
                                }
                                .disabled(isProxyHealthCheckRunning || isProxyRequestTestRunning)

                                Button {
                                    runProxyGuidedStudyTest()
                                } label: {
                                    Text(isProxyRequestTestRunning ? "Sending test..." : "Test Guided Study")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(SeekTheme.maroonAccent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(SeekTheme.maroonAccent, lineWidth: 1)
                                        )
                                }
                                .disabled(isProxyHealthCheckRunning || isProxyRequestTestRunning)
                            }

                            if !proxyDebugLog.isEmpty {
                                Text(proxyDebugLog)
                                    .font(.system(size: 12))
                                    .foregroundColor(SeekTheme.textSecondary)
                            }
                        }
                        .padding(16)
                        #endif

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

                                Text("Remote URL sanity check")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(SeekTheme.textPrimary)
                                    .padding(.top, 2)

                                Text("index: \(RemoteConfig.indexURL()?.absoluteString ?? "invalid")")
                                    .font(.system(size: 12))
                                    .foregroundColor(SeekTheme.textSecondary)

                                Text("sample: \(RemoteConfig.chapterURL(scriptureId: "quran", bookId: "al-baqara", chapter: 2)?.absoluteString ?? "invalid")")
                                    .font(.system(size: 12))
                                    .foregroundColor(SeekTheme.textSecondary)
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
            refreshEntitlementStatus()
            refreshStreakStatus()
            refreshStudyUsageStatus()
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

    private func refreshStreakStatus() {
        streakState = StreakStore().load()
    }

    private func simulateLastEngagedDaysAgo(_ days: Int) {
        guard var state = streakState else { return }
        guard let targetDay = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }
        state.lastEngagedAt = Calendar.current.startOfDay(for: targetDay)
        StreakStore().save(state)
        refreshStreakStatus()
    }

    private func debugFormattedEngagedDay(_ date: Date?) -> String {
        guard let date else { return "none" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        if calendar.isDateInToday(date) {
            return "\(formatter.string(from: date)) (today)"
        }
        if calendar.isDateInYesterday(date) {
            return "\(formatter.string(from: date)) (yesterday)"
        }
        return formatter.string(from: date)
    }

    private func refreshEntitlementStatus() {
        EntitlementManager.shared.applySandboxOverrideIfNeeded()
        entitlementState = EntitlementManager.shared.state
    }

    private func refreshStudyUsageStatus() {
        studyUsageState = StudyUsageTracker.shared.currentState()
    }

    private func debugFormattedEntitlementDate(_ date: Date?) -> String {
        guard let date else { return "None" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func debugFormattedSource(_ source: String?) -> String {
        guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else {
            return "Unknown"
        }
        switch source.lowercased() {
        case "sandbox":
            return "Sandbox"
        case "storekit":
            return "StoreKit"
        case "debug":
            return "Debug"
        default:
            return source.prefix(1).uppercased() + source.dropFirst().lowercased()
        }
    }

    @ViewBuilder
    private func debugStatusRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(SeekTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SeekTheme.textPrimary)
        }
    }

    private func runProxyHealthCheck() {
        guard !isProxyHealthCheckRunning, !isProxyRequestTestRunning else { return }
        isProxyHealthCheckRunning = true
        proxyDebugLog = "Testing GET /health..."

        Task { @MainActor in
            defer { isProxyHealthCheckRunning = false }
            do {
                let result = try await GuidedStudyProxyDiagnostics.testHealth(baseURL: RemoteConfig.guidedStudyProxyBaseURL)
                proxyDebugLog = "GET /health -> HTTP \(result.statusCode)\n\(result.snippet)"
            } catch {
                proxyDebugLog = "GET /health failed: \(error.localizedDescription)"
            }
        }
    }

    private func runProxyGuidedStudyTest() {
        guard !isProxyHealthCheckRunning, !isProxyRequestTestRunning else { return }
        isProxyRequestTestRunning = true
        proxyDebugLog = "Sending POST /guided-study test payload..."

        Task { @MainActor in
            defer { isProxyRequestTestRunning = false }
            do {
                let result = try await GuidedStudyProxyDiagnostics.testGuidedStudy(
                    baseURL: RemoteConfig.guidedStudyProxyBaseURL,
                    locale: Locale.current.identifier
                )
                proxyDebugLog = "POST /guided-study -> HTTP \(result.statusCode)\n\(result.snippet)"
            } catch {
                proxyDebugLog = "POST /guided-study failed: \(error.localizedDescription)"
            }
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
