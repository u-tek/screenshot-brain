import Core
import DesignSystem
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share to Screenshot Brain": copies the shared images into the App Group's inbox and says so.
/// Reading them (text, nudity filter, classification) happens in the app, which has the memory
/// for it; share extensions don't.
final class ShareViewController: UIViewController {
    private let status = ShareStatus()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareConfirmation(status: status) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        Task {
            var saved = 0
            for provider in providers where await Self.deposit(provider) {
                saved += 1
            }
            status.saved = saved
            status.isDone = true
        }
    }

    /// The file only exists inside the completion handler, so it's copied there.
    private nonisolated static func deposit(_ provider: NSItemProvider) async -> Bool {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                let saved = url.map { (try? SharedInbox.deposit($0)) != nil } ?? false
                continuation.resume(returning: saved)
            }
        }
    }
}

@MainActor
final class ShareStatus: ObservableObject {
    @Published var saved = 0
    @Published var isDone = false
}

struct ShareConfirmation: View {
    @ObservedObject var status: ShareStatus
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                AppMark()
                if status.isDone {
                    SmallLabel(status.saved == 1 ? "1 screenshot" : "\(status.saved) screenshots")
                    MistHeadline(status.saved > 0 ? "Got them. **Open the app.**" : "That one didn't **come through.**", size: 26)
                    MistBody(status.saved > 0
                        ? "Screenshot Brain reads them next time it's open, **on this iPhone.**"
                        : "Try sharing it again from Photos.")
                } else {
                    SmallLabel("Saving")
                    MistHeadline("Just a **second.**", size: 26)
                }
                Button(action: onClose) {
                    Chip("Done", closable: true)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .disabled(!status.isDone)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [SBColor.mistTop, SBColor.mistBottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: SBRadius.card, style: .continuous)
            )
            .padding(16)
        }
    }
}
