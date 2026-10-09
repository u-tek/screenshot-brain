import Core
import DesignSystem
import Paywall
import Store
import SwiftUI

/// Recap time, premium, the privacy statement, the account. Opened from the gear on Home.
struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    @State private var isDeleting = false
    @State private var deleteFailed = false
    @State private var showsDebug = false
    @State private var restoreMessage: String?
    var onShowPlans: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            SBNavHeader(onLeading: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Settings")
                            .sbText(.large)
                            .accessibilityAddTraits(.isHeader)
                        MistBody("Yours, **on this iPhone.**", alignment: .leading)
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
                            guard model.purchases.isAvailable else {
                                restoreMessage = "Purchases aren't set up in this build."
                                return
                            }
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
                        if model.account?.isLocalOnly == true {
                            SmallLabel("Test build: kept on this iPhone only")
                        } else if let name = model.account?.givenName {
                            SmallLabel("Signed in with Apple as \(name)")
                        } else {
                            SmallLabel("Signed in with Apple")
                        }
                        Button {
                            confirmsDelete = true
                        } label: {
                            Text(isDeleting ? "Deleting…" : "Delete account")
                                .font(SBFont.body(16, weight: .semibold))
                                .foregroundStyle(SBKind.events.core)
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
                .padding(.horizontal, SBSpace.gutter)
                .padding(.top, 12)
                .padding(.bottom, 48)
            }
        }
        .sbScreen(.calm)
        .toolbar(.hidden, for: .navigationBar)
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
            let minutes = NightlyRecap.recapMinutes(model.answers)
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.updateAnswers { $0.recapMinutes = (parts.hour ?? 21) * 60 + (parts.minute ?? 0) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SBLabel(title)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous).fill(SBColor.surface))
        }
    }
}
