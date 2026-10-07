import Core
import DesignSystem
import Paywall
import Store
import SwiftUI

/// Recap time, the privacy statement, the account. Purchases arrive with the paywall (M8).
struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmsDelete = false
    @State private var isDeleting = false
    @State private var deleteFailed = false
    @State private var showsDebug = false
    @State private var restoreMessage: String?
    var onShowPlans: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        SmallLabel("Settings")
                        MistHeadline("Yours, **on this iPhone.**", size: 32, alignment: .leading)
                    }

                    section("Recap") {
                        DatePicker(selection: recapTime, displayedComponents: .hourAndMinute) {
                            Text("Recap time")
                                .font(SBFont.body(16))
                                .foregroundStyle(SBColor.ink)
                        }
                        SmallLabel("One a night at most, and only when there's something new.")
                    }

                    section("Premium") {
                        SmallLabel(model.isPremium ? "Premium is on. Thanks." : "The widget, the all-time Reveal and full monthly stats.")
                        if !model.isPremium {
                            Button("See plans", action: onShowPlans)
                                .font(SBFont.body(16, weight: .semibold))
                                .foregroundStyle(SBColor.ink)
                                .buttonStyle(.plain)
                        }
                        Button("Restore purchases") {
                            Task {
                                let restored = (try? await model.purchases.restore()) ?? false
                                restoreMessage = restored ? "Restored." : "Nothing to restore on this Apple ID."
                            }
                        }
                        .font(SBFont.body(16))
                        .foregroundStyle(SBColor.ink)
                        .buttonStyle(.plain)
                        if let restoreMessage {
                            SmallLabel(restoreMessage)
                        }
                    }

                    section("Privacy") {
                        MistBody("Screenshot Brain reads your screenshots **on this iPhone.** The screenshots and the text in them never leave it. Only your progress (what you kept, did and dropped, and your answers) syncs to your iCloud, so a new phone picks up where you were. Analytics are counts only, never content.", alignment: .leading)
                        if let policy = model.configuration.privacyPolicyURL {
                            Link("Privacy policy", destination: policy)
                                .font(SBFont.body(15))
                                .foregroundStyle(SBColor.ink)
                        }
                    }

                    section("Account") {
                        if let name = model.account?.givenName {
                            SmallLabel("Signed in with Apple as \(name)")
                        } else {
                            SmallLabel("Signed in with Apple")
                        }
                        Button {
                            confirmsDelete = true
                        } label: {
                            Text(isDeleting ? "Deleting…" : "Delete account")
                                .font(SBFont.body(16, weight: .semibold))
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeleting)
                    }

                    if let email = model.configuration.supportEmail, let url = URL(string: "mailto:\(email)") {
                        section("Contact") {
                            Link(destination: url) {
                                Text("Say hello")
                                    .font(SBFont.body(16))
                                    .foregroundStyle(SBColor.ink)
                            }
                            SmallLabel(email)
                        }
                    }

                    #if DEBUG
                    section("Debug") {
                        Button("Benchmark, accuracy and design lab") { showsDebug = true }
                            .font(SBFont.body(16))
                            .foregroundStyle(SBColor.ink)
                            .buttonStyle(.plain)
                    }
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .background {
                LinearGradient(colors: [SBColor.mistTop, SBColor.mistBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showsDebug) {
            DebugMenu()
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                isDeleting = true
                Task {
                    do {
                        try await model.deleteAccount()
                    } catch {
                        deleteFailed = true
                    }
                    isDeleting = false
                }
            }
        } message: {
            Text("This deletes your progress from iCloud and this iPhone and signs you out of Sign in with Apple. Your screenshots stay in Photos.")
        }
        .alert("Couldn't delete it all", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check you're online and try again.")
        }
    }

    private var recapTime: Binding<Date> {
        Binding {
            let minutes = model.answers.recapMinutes ?? 21 * 60
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.updateAnswers { $0.recapMinutes = (parts.hour ?? 21) * 60 + (parts.minute ?? 0) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SmallLabel(title)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sbGlass(in: RoundedRectangle(cornerRadius: SBRadius.card, style: .continuous))
        }
    }
}
