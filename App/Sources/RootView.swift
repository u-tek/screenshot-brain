import DesignSystem
import SwiftUI

/// The first-open flow so far: the pitch, then the first guessing question.
/// The full flow (sign-in, photo access, scan, Reveal) arrives in M4.
struct RootView: View {
    @State private var step: Step = .welcome

    enum Step {
        case welcome
        case question
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeScreen {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .question }
                }
                .transition(.opacity)
            case .question:
                GuessQuestionScreen(onSkip: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .welcome }
                })
                .transition(.opacity)
            }
        }
    }
}
