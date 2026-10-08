import SwiftUI

/// A number that counts up when it appears, with a light haptic tick as it goes.
/// Shows its final value at once under Reduce Motion, in snapshots, and to VoiceOver.
public struct CountingNumber: View {
    private let target: Int
    private let font: Font
    @State private var shown: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lightIsStill) private var lightIsStill

    public init(_ target: Int, font: Font) {
        self.target = target
        self.font = font
        self._shown = State(initialValue: 0)
    }

    public var body: some View {
        Text(shown.formatted())
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .foregroundStyle(SBColor.ink)
            .task(id: target) {
                guard !reduceMotion, !lightIsStill, target > 0 else {
                    shown = target
                    return
                }
                let steps = min(24, target)
                let pause = UInt64(SBMotion.countUpDuration / Double(steps) * 1_000_000_000)
                for step in 1...steps {
                    try? await Task.sleep(nanoseconds: pause)
                    let progress = Double(step) / Double(steps)
                    let eased = 1 - pow(1 - progress, 3)
                    shown = Int((Double(target) * eased).rounded())
                    if step.isMultiple(of: 2) {
                        Haptics.tick()
                    }
                }
                shown = target
            }
            .accessibilityLabel(Text(target.formatted()))
    }
}

/// Story progress: the v4 story bars.
public struct ProgressSegments: View {
    private let count: Int
    private let current: Int

    public init(count: Int, current: Int) {
        self.count = count
        self.current = current
    }

    public var body: some View {
        SBStoryBars(count: count, current: current)
    }
}

/// Label-value rows in small monospaced type, like a swatch card's data.
public struct DataRows: View {
    private let rows: [(String, String)]

    public init(_ rows: [(String, String)]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 0) {
                    Text(rows[index].0.uppercased())
                        .tracking(0.9)
                        .frame(width: 92, alignment: .leading)
                        .foregroundStyle(SBColor.ink2)
                    Text(rows[index].1)
                        .foregroundStyle(SBColor.ink)
                }
                .font(SBFont.mono(12))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
