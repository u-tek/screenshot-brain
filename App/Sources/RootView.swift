import SwiftUI

/// Placeholder until the art direction is approved and the first-open flow is built (M4).
struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(spacing: 8) {
            Text("Screenshot Brain")
                .font(.title2.weight(.semibold))
            switch environment.database {
            case .ready:
                Text("Store ready")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
