import SwiftUI

/// Two-tone headline: dim words with one bright phrase, marked with `**`: "You saved it **for a reason.**"
public struct MistHeadline: View {
    private let markup: String
    private let size: CGFloat
    private let alignment: TextAlignment
    /// Headlines scale with Dynamic Type, relative to the largest title style.
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    public init(_ markup: String, size: CGFloat = 32, alignment: TextAlignment = .center) {
        assert(markup.components(separatedBy: "**").count <= 3, "One bold phrase per headline, never more")
        self.markup = markup
        self.size = size
        self.alignment = alignment
    }

    public var body: some View {
        Text(MistMarkup.attributed(markup, size: size * scale, light: .regular, bold: .regular, lightColor: SBColor.ink2))
            .tracking(-0.02 * size * scale)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Short body copy with an occasional bold phrase, marked with `**`.
public struct MistBody: View {
    private let markup: String
    private let size: CGFloat
    private let alignment: TextAlignment

    public init(_ markup: String, size: CGFloat = 15, alignment: TextAlignment = .center) {
        self.markup = markup
        self.size = size
        self.alignment = alignment
    }

    public var body: some View {
        Text(MistMarkup.attributed(markup, size: size, light: .regular, bold: .medium, lightColor: SBColor.ink2, scalesWithTextStyle: true))
            .multilineTextAlignment(alignment)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Tiny grey label: "Question 1", "Saved 3 weeks ago".
public struct SmallLabel: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(SBFont.label)
            .foregroundStyle(SBColor.inkSecondary)
    }
}

enum MistMarkup {
    static func attributed(
        _ markup: String,
        size: CGFloat,
        light: Font.Weight,
        bold: Font.Weight,
        lightColor: Color,
        scalesWithTextStyle: Bool = false
    ) -> AttributedString {
        var result = AttributedString()
        for (index, part) in markup.components(separatedBy: "**").enumerated() where !part.isEmpty {
            let isBold = index % 2 == 1
            var run = AttributedString(part)
            let weight = isBold ? bold : light
            run.font = scalesWithTextStyle
                ? Font.system(SBFont.textStyle(for: size), design: .default, weight: weight)
                : Font.system(size: size, weight: weight)
            run.foregroundColor = isBold ? SBColor.ink : lightColor
            result.append(run)
        }
        return result
    }
}
