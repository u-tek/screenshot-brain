import AuthenticationServices
import DesignSystem
import SwiftUI

/// Sign in with Apple, so progress survives a crash or a new phone.
struct SignInScreen: View {
    var palette: LightPalette = .sampleTopScreenshots
    /// Sideload test builds only.
    var allowsLocal = false
    var onLocal: () -> Void = {}
    var onResult: (Result<ASAuthorization, Error>) -> Void = { _ in }
    @State private var failed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppMark()
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            Spacer()
            SmallLabel("Before we start")
                .padding(.bottom, 10)
            MistHeadline("So you never lose **your progress.**", size: 34, alignment: .leading)
                .padding(.bottom, 14)
            MistBody("Your guesses, your score and what you've ticked off follow you to a new phone. **Your screenshots never leave this one.**", alignment: .leading)
                .padding(.bottom, 28)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                if case .failure(let error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                    failed = true
                }
                onResult(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            // The button doesn't restyle itself when the appearance changes; rebuild it.
            .id(colorScheme)
            .frame(height: 58)
            .clipShape(Capsule())
            .padding(.bottom, 14)

            SmallLabel(failed ? "That didn't go through. Give it another go?" : "Just your Apple ID. No email, no password.")
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)

            if allowsLocal {
                Button(action: onLocal) {
                    Chip("Test build: continue on this iPhone")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 24)
        .background {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    // The lens sits in the sweep with its lower rim just past the light's edge.
                    LightField(.sweep(palette), drifts: true)
                    GlassLens(diameter: size.width * 0.52)
                        .position(x: size.width * 0.66, y: size.height * 0.27)
                }
                .frame(width: size.width, height: size.height)
            }
            .ignoresSafeArea()
        }
    }
}
