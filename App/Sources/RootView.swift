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
            screen(for: model.step)
                .id(model.step)
                .transition(.opacity)
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
