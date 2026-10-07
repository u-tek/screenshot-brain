import SwiftUI

/// ✓: an orange circle with a white check.
public struct DoneMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(SBColor.accent))
            .accessibilityLabel(Text("Done"))
    }
}

/// ✕: a frosted circle with a grey cross.
public struct DropMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: size * 0.3, weight: .regular))
            .foregroundStyle(SBColor.inkSecondary)
            .frame(width: size, height: size)
            .sbGlass(in: Circle())
            .accessibilityLabel(Text("Drop"))
    }
}

/// "Done X of Y": a huge thin number, the total in Semibold, and a hairline track.
public struct ScoreView: View {
    private let done: Int
    private let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(done)")
                    .font(SBFont.number(120))
                    .foregroundStyle(SBColor.ink)
                Text("of \(total)")
                    .font(SBFont.body(20, weight: .semibold))
                    .foregroundStyle(SBColor.ink)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SBColor.hairline).frame(height: 1)
                    Capsule()
                        .fill(SBColor.accent)
                        .frame(width: proxy.size.width * CGFloat(total > 0 ? Double(done) / Double(total) : 0), height: 2)
                }
            }
            .frame(height: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Done \(done) of \(total)"))
    }
}

/// The thin line with a small orange dot: the hour histogram and "Coming up" dates.
public struct TimelineLine: View {
    private let values: [Double]
    private let highlight: Int

    /// `values` are bar heights 0...1; `highlight` is the index that gets the orange dot.
    public init(values: [Double], highlight: Int) {
        self.values = values
        self.highlight = highlight
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(values.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if index == highlight {
                            Circle().fill(SBColor.accent).frame(width: 7, height: 7)
                        }
                        Capsule()
                            .fill(index == highlight ? SBColor.ink : SBColor.inkSecondary.opacity(0.35))
                            .frame(width: 1.5, height: max(4, CGFloat(values[index]) * 64))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)
            Rectangle().fill(SBColor.hairline).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}
