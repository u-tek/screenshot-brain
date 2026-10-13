import Core
import DesignSystem
import PhotosUI
import ScanEngine
import SwiftUI

/// Our pre-prompt, then the system's. If the answer is no, screenshots can still come in through
/// the picker or the share sheet.
struct PhotoAccessScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.photoAccess == .denied {
            ShareRouteScreen(palette: model.palette) {
                model.startScan()
            }
        } else {
            PhotoAccessPrompt(palette: model.palette) {
                Task { await model.requestPhotoAccess() }
            }
        }
    }
}

struct PhotoAccessPrompt: View {
    var palette: LightPalette = .sampleTopScreenshots
    var onAllow: () -> Void = {}

    var body: some View {
        QuestionLayout(
            label: "Photo access",
            headline: "Let's see what **you've been saving.**",
            subtext: "Screenshot Brain reads your screenshots on this iPhone. **They never leave it.**",
            light: .sweep(palette).mirrored(),
            palette: palette,
            footnote: "Full access gets you the whole Reveal",
            actionTitle: "Allow access",
            onNext: onAllow
        ) {
            FrostedCard(palette: palette) {
                DataRows([
                    ("Reads", "Screenshots only"),
                    ("Where", "On this iPhone"),
                    ("Uploads", "None, ever"),
                ])
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
        }
    }
}

/// No photo access: pick screenshots without it, or share them in from Photos.
struct ShareRouteScreen: View {
    var palette: LightPalette = .sampleTopScreenshots
    var onShared: () -> Void = {}
    @State private var picked: [PhotosPickerItem] = []
    @State private var isSaving = false
    @State private var couldntRead = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 620
            ZStack {
                LightField(.sweep(palette), drifts: true)
                    .ignoresSafeArea()

                let content = VStack(spacing: 0) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Chip("Allow in Settings")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    Spacer(minLength: 8)
                    GlassLens(diameter: compact ? 72 : 112)
                    Spacer(minLength: 8)

                    SmallLabel("No photo access")
                        .padding(.bottom, 10)
                    MistHeadline("Fair enough. **Hand us a few.**", size: compact ? 28 : 32)
                        .padding(.horizontal, 28)
                    MistBody("Pick some screenshots and we'll read just those. **Nothing else.**")
                        .padding(.top, 10)
                        .padding(.horizontal, 36)

                    Spacer(minLength: 16)

                    FrostedCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            SmallLabel("Or later, from Photos")
                            DataRows([
                                ("01", "Select screenshots"),
                                ("02", "Tap Share"),
                                ("03", "Pick Screenshot Brain"),
                            ])
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 16)

                    SmallLabel(isSaving ? "Reading what you picked" : (couldntRead ? "Couldn't read those. Try again." : "Ten or more makes a good Reveal"))
                        .padding(.bottom, 12)
                    PhotosPicker(selection: $picked, maxSelectionCount: 60, matching: .screenshots) {
                        ActionBarLabel("Pick screenshots", systemImage: "plus", palette: palette)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .disabled(isSaving)
                }

                if dynamicTypeSize.isAccessibilitySize {
                    // Large text outgrows the screen: scroll, so the action stays reachable.
                    ScrollView {
                        content.frame(width: proxy.size.width, alignment: .top)
                            .frame(minHeight: proxy.size.height)
                    }
                } else {
                    content.frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .onChange(of: picked) { items in
            guard !items.isEmpty else { return }
            isSaving = true
            couldntRead = false
            Task {
                var deposited = 0
                // The picker runs outside the app and needs no photo access. Each picked image
                // goes into the inbox, and the scan reads it like a shared one.
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "img"
                        if (try? SharedInbox.deposit(data: data, fileExtension: fileExtension)) != nil {
                            deposited += 1
                        }
                    }
                }
                picked = []
                isSaving = false
                if deposited > 0 {
                    onShared()
                } else {
                    couldntRead = true
                }
            }
        }
    }
}
