import AuthenticationServices
import Core
import DesignSystem
import Foundation
import Reveal
import ScanEngine
import Store
import SwiftUI

/// The app's state: who's signed in, how far through onboarding they are (persisted and synced,
/// so it's never repeated), photo access, the scan, and the Reveal.
@MainActor
final class AppModel: ObservableObject {
    let services: AppServices?
    let analytics: Analytics
    let configuration: AppConfiguration
    private let sync: CloudSync?

    @Published private(set) var answers: OnboardingAnswers
    @Published private(set) var account: Account?
    @Published private(set) var photoAccess: PhotoAccess
    /// Screenshots read so far, counting earlier runs, for the onboarding counter.
    @Published private(set) var screenshotsRead = 0
    /// Screenshots there are to read, counting ones read in earlier runs.
    @Published private(set) var screenshotsFound = 0
    @Published private(set) var isScanning = false
    @Published private(set) var story: RevealStory?
    /// The light of the app: the user's own colours once screenshots have been read.
    @Published private(set) var palette: LightPalette = .sampleTopScreenshots
    /// Where onboarding resumes after photo access is granted again on a new phone.
    private var resumeStep: OnboardingStep?
    private var syncTask: Task<Void, Never>?

    init(services: AppServices?, analytics: Analytics, configuration: AppConfiguration) {
        self.services = services
        self.analytics = analytics
        self.configuration = configuration
        self.sync = services.flatMap { services in
            configuration.cloudKitContainerIdentifier.map { CloudSync(database: services.database, containerIdentifier: $0) }
        }
        self.account = AccountStore.load()
        self.photoAccess = ScreenshotLibrary.currentAccess()
        self.answers = (try? services?.database.onboardingAnswers()) ?? OnboardingAnswers()
        // Signed out (or the account was revoked): everything after sign-in waits for it.
        if account == nil, answers.step > .signIn {
            answers.step = .signIn
        }
        refreshPalette()
    }

    static func live() -> AppModel {
        let configuration = AppConfiguration.main
        return AppModel(
            services: AppServices.shared,
            analytics: .telemetryDeck(appID: configuration.telemetryDeckAppID),
            configuration: configuration
        )
    }

    var step: OnboardingStep {
        answers.step
    }

    // MARK: Launch

    /// Checks the account is still valid, resumes where onboarding left off, and picks up new
    /// screenshots.
    func start() async {
        if let account, !(await AccountStore.isStillAuthorised(account)) {
            signOutLocally()
            return
        }
        if account != nil {
            await syncNow()
        }
        resolveResume()
        if step > .signIn {
            startScan()
        }
    }

    /// Back in the app: photo access may have changed in Settings, and screenshots may have been
    /// shared in.
    func becameActive() {
        let previous = photoAccess
        photoAccess = ScreenshotLibrary.currentAccess()
        guard account != nil, step >= .photoAccess else { return }
        if step == .photoAccess, previous != photoAccess, hasPhotoAccess {
            advanceAfterPhotoAccess()
        }
        startScan()
    }

    var hasPhotoAccess: Bool {
        photoAccess == .full || photoAccess == .limited
    }

    /// On a new phone, synced progress can be past photo access while this device hasn't been
    /// granted it yet: ask again, then carry on from where they were.
    private func resolveResume() {
        guard account != nil, step > .photoAccess, photoAccess == .notDetermined else { return }
        resumeStep = step
        answers.step = .photoAccess
    }

    // MARK: Onboarding progress

    /// "Show me" on the pitch. Someone already signed in (the Keychain outlives a reinstall)
    /// goes straight on.
    func finishPitch() {
        analytics.track(.onboardingStarted)
        advance(to: account == nil ? .signIn : .photoAccess)
    }

    func advance(to step: OnboardingStep) {
        guard step != answers.step else { return }
        answers.step = step
        if step == .home, answers.completedAt == nil {
            answers.completedAt = Date()
        }
        persist()
    }

    func updateAnswers(_ change: (inout OnboardingAnswers) -> Void) {
        change(&answers)
        persist()
    }

    private func persist() {
        answers.updatedAt = Date()
        try? services?.database.save(answers)
        scheduleSync()
    }

    // MARK: Account

    func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        else { return }
        var account = Account(userID: credential.user, givenName: credential.fullName?.givenName ?? AccountStore.load()?.givenName)
        AccountStore.save(account)
        self.account = account
        analytics.track(.signedIn)

        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        Task {
            if let code, let token = await AccountServer.exchange(authorizationCode: code, configuration: configuration) {
                account.refreshToken = token
                AccountStore.save(account)
                self.account = account
            }
            // Progress syncs from the moment of sign-in: a returning user resumes where they were.
            await syncNow()
            if step <= .signIn {
                advance(to: .photoAccess)
            }
            resolveResume()
        }
    }

    private func signOutLocally() {
        AccountStore.delete()
        account = nil
        answers.step = .signIn
    }

    /// Account deletion: iCloud data, the Sign in with Apple token, and everything on the device.
    func deleteAccount() async throws {
        if let sync {
            try await sync.deleteEverything()
        }
        if let token = account?.refreshToken {
            try await AccountServer.revoke(refreshToken: token, configuration: configuration)
        }
        try services?.database.eraseAll()
        if let thumbnails = try? AppGroup.directory(.thumbnails) {
            try? FileManager.default.removeItem(at: thumbnails)
        }
        AccountStore.delete()
        account = nil
        answers = OnboardingAnswers()
        story = nil
    }

    // MARK: Photos and the scan

    func requestPhotoAccess() async {
        photoAccess = await ScreenshotLibrary.requestAccess()
        switch photoAccess {
        case .full:
            analytics.track(.photoAccessFull)
        case .limited:
            analytics.track(.photoAccessLimited)
        case .denied, .notDetermined:
            analytics.track(.photoAccessDenied)
        }
        if hasPhotoAccess {
            startScan()
            advanceAfterPhotoAccess()
        }
    }

    private func advanceAfterPhotoAccess() {
        let next = resumeStep ?? .questions
        resumeStep = nil
        advance(to: next)
    }

    /// Reads new library screenshots (with photo access) and anything shared in through the
    /// share extension (with or without it).
    func startScan() {
        guard let services, !isScanning else { return }
        isScanning = true
        let hasPhotoAccess = hasPhotoAccess
        Task {
            do {
                let baseline = try await Task.detached(priority: .userInitiated) { () -> Int in
                    if hasPhotoAccess {
                        try services.pipeline.discover()
                        try services.database.applyPendingRemoteStates()
                    }
                    return try services.database.processedCount()
                }.value
                screenshotsRead = baseline
                screenshotsFound = baseline

                let shared = try await services.pipeline.importShared(progress: progressReporter(base: baseline))
                if shared > 0 {
                    analytics.track(.screenshotsShared, counts: ["screenshots": shared])
                    if step == .photoAccess {
                        advance(to: .questions)
                    }
                }
                if hasPhotoAccess {
                    let afterShared = try services.database.processedCount()
                    try await services.pipeline.readPending(includeBackfill: true, progress: progressReporter(base: afterShared))
                }
                analytics.track(.scanCompleted, counts: ["screenshots": screenshotsFound])
            } catch {
                Log.scan.error("Scan failed: \(error.localizedDescription, privacy: .public)")
            }
            isScanning = false
            moveOnIfReady()
            refreshPalette()
            scheduleSync()
            if let services = self.services {
                await WidgetRefresher.refresh(services: services)
            }
        }
    }

    /// Progress from one scan run, counted on top of what earlier runs read.
    private func progressReporter(base: Int) -> @Sendable (ScanProgress) -> Void {
        { progress in
            Task { @MainActor in
                self.screenshotsRead = base + progress.read
                self.screenshotsFound = base + progress.total
                // Every 24 screenshots, let the light take on the user's colours.
                if progress.read > 0, progress.read % 24 == 0 { self.refreshPalette() }
                self.moveOnIfReady()
            }
        }
    }

    /// The Reveal can start once the facts are known (timestamps, straight from discovery) and
    /// enough screenshots have been read for category claims to mean something.
    var isReadyForReveal: Bool {
        !isScanning || screenshotsRead >= min(screenshotsFound, 120)
    }

    /// After the last question: straight to the Reveal, or a moment's wait while the scan
    /// catches up.
    func finishQuestions() {
        advance(to: isReadyForReveal ? .reveal : .finishingUp)
    }

    private func moveOnIfReady() {
        if step == .finishingUp, isReadyForReveal {
            advance(to: .reveal)
        }
    }

    func prepareReveal() async {
        guard let database = services?.database else { return }
        let answers = self.answers
        // Limited access and shared-in screenshots get the Reveal built for a handful.
        let isLimited = photoAccess != .full
        story = try? await Task.detached(priority: .userInitiated) {
            try RevealBuilder.build(database: database, answers: answers, isLimited: isLimited)
        }.value
        if let story {
            palette = story.palette
            analytics.track(.revealStarted, counts: ["screenshots": story.total])
        }
    }

    private func refreshPalette() {
        guard let items = try? services?.database.recentSafeItems(limit: 12), !items.isEmpty else { return }
        let colors = items.flatMap { item in
            item.palette.map { PaletteColor(red: $0.red, green: $0.green, blue: $0.blue, weight: $0.weight / Double(items.count)) }
        }
        if let extracted = LightPalette(extracted: colors) {
            palette = extracted
        }
    }

    // MARK: Sync

    private func scheduleSync() {
        guard account != nil, sync != nil else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    private func syncNow() async {
        guard let sync else { return }
        await sync.sync()
        if let synced = try? services?.database.onboardingAnswers(), synced.step > answers.step {
            answers = synced
        }
    }
}
