import Core
import DesignSystem
import SwiftUI

/// Shows whichever step the user is on. The step is persisted and synced, so onboarding resumes
/// where it left off and is never repeated.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if model.services == nil {
                StorageUnavailable(palette: model.palette)
            } else {
                screen(for: model.step)
                    .id(model.step)
                    .transition(.opacity)
            }
        }
        .animation(SBMotion.settle, value: model.step)
        .task {
            await model.start()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.becameActive()
            } else if phase == .background {
                model.wentToBackground()
            }
        }
        .onOpenURL { url in
            model.open(url)
        }
    }

    @ViewBuilder
    private func screen(for step: OnboardingStep) -> some View {
        switch step {
        case .pitch:
            WelcomeScreen(palette: model.palette) {
                model.finishPitch()
            }
        case .signIn:
            SignInScreen(
                palette: model.palette,
                allowsLocal: model.configuration.allowsLocalAccount,
                onLocal: { model.continueOnThisPhone() },
                onResult: { result in model.handleSignIn(result) }
            )
        case .photoAccess:
            PhotoAccessScreen()
        case .questions:
            QuestionsFlow()
        case .finishingUp:
            FinishingUpScreen(palette: model.palette, read: model.screenshotsRead, total: model.screenshotsFound)
        case .reveal:
            RevealHost()
        case .triage, .score, .paywall, .notifications, .widgetGuide, .home:
            AfterRevealFlow()
        }
    }
}

/// The database couldn't be opened (no space left, or the container is unavailable). Nothing
/// could be saved, so say so rather than run on and lose everything.
private struct StorageUnavailable: View {
    let palette: LightPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            MistHeadline("Couldn't open **your saved things.**", size: 32, alignment: .leading)
            MistBody("Check there's some free space on this iPhone, then close Screenshot Brain and open it again.", alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LightField(.sweep(palette), drifts: false).ignoresSafeArea())
    }
}
