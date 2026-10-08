import SwiftUI

/// ✓: a warm white circle with a dark check.
public struct DoneMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public var body: some View {
        SBIconView(.check, size: size * 0.5)
            .foregroundStyle(SBColor.ground)
            .frame(width: size, height: size)
            .background(Circle().fill(SBColor.accent))
            .accessibilityLabel(Text("Done"))
    }
}

/// ✕: a dark circle with a dim cross.
public struct DropMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public var body: some View {
        SBIconView(.x, size: size * 0.45)
            .foregroundStyle(SBColor.ink2)
            .frame(width: size, height: size)
            .background(Circle().fill(SBColor.surface2))
            .accessibilityLabel(Text("Drop"))
    }
}

/// "Done X of Y": a huge light number, the total dimmed, and a progress track.
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
                    .sbText(.unit, color: SBColor.ink2)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SBColor.warm(0.14)).frame(height: 4)
                    Capsule()
                        .fill(SBColor.accent)
                        .frame(width: proxy.size.width * CGFloat(total > 0 ? Double(done) / Double(total) : 0), height: 4)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Done \(done) of \(total)"))
    }
}

/// The thin line with a small warm white dot: the hour histogram and "Coming up" dates.
public struct TimelineLine: View {
    private let values: [Double]
    private let highlight: Int

    /// `values` are bar heights 0...1; `highlight` is the index that gets the dot.
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
                            .fill(index == highlight ? SBColor.accent : SBColor.warm(0.25))
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
