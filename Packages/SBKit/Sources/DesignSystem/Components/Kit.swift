import SwiftUI

// The v4 components: one per job. Screens use these instead of their own colours, fonts and buttons.

// MARK: - Type

/// The type roles. Numbers and the Reveal serif are fixed compositions; the rest scale with
/// Dynamic Type.
public enum SBTextRole: Sendable, CaseIterable {
    /// Screen titles.
    case large
    /// A title beside a back or close button.
    case nav
    /// The big reading (the score).
    case numXL
    /// Numbers in tiles and cards.
    case numL
    /// The unit after a number.
    case unit
    /// Item names.
    case title
    /// Secondary text.
    case body
    /// Small mono caps.
    case label
    /// Small mono caps, dimmed.
    case labelDim
    /// Reveal headlines.
    case story
    case storySmall
    /// The app's name beside its mark.
    case mark

    struct Spec {
        let size: CGFloat
        let weight: Font.Weight
        let design: Font.Design
        /// Tracking in em.
        let tracking: CGFloat
        let uppercase: Bool
        let color: Color
        /// The text style it scales with, or nil for a fixed size.
        let style: Font.TextStyle?
    }

    var spec: Spec {
        switch self {
        case .large: Spec(size: 40, weight: .regular, design: .default, tracking: -0.02, uppercase: false, color: SBColor.ink, style: .largeTitle)
        case .nav: Spec(size: 22, weight: .regular, design: .default, tracking: -0.01, uppercase: false, color: SBColor.ink, style: .title2)
        case .numXL: Spec(size: 96, weight: .light, design: .default, tracking: -0.02, uppercase: false, color: SBColor.ink, style: nil)
        case .numL: Spec(size: 44, weight: .light, design: .default, tracking: -0.02, uppercase: false, color: SBColor.ink, style: nil)
        case .unit: Spec(size: 17, weight: .regular, design: .default, tracking: 0, uppercase: false, color: SBColor.ink, style: .body)
        case .title: Spec(size: 17, weight: .semibold, design: .default, tracking: -0.01, uppercase: false, color: SBColor.ink, style: .headline)
        case .body: Spec(size: 15, weight: .regular, design: .default, tracking: 0, uppercase: false, color: SBColor.ink2, style: .subheadline)
        case .label: Spec(size: 11, weight: .medium, design: .monospaced, tracking: 0.08, uppercase: true, color: SBColor.ink, style: .caption2)
        case .labelDim: Spec(size: 11, weight: .medium, design: .monospaced, tracking: 0.08, uppercase: true, color: SBColor.ink2, style: .caption2)
        case .story: Spec(size: 52, weight: .regular, design: .serif, tracking: 0.14, uppercase: true, color: SBColor.ink, style: nil)
        case .storySmall: Spec(size: 34, weight: .regular, design: .serif, tracking: 0.14, uppercase: true, color: SBColor.ink, style: nil)
        case .mark: Spec(size: 15, weight: .semibold, design: .default, tracking: -0.01, uppercase: false, color: SBColor.ink, style: .subheadline)
        }
    }

    /// The role's font at its default size, for places that need a `Font` value.
    public var font: Font {
        let spec = spec
        return .system(size: spec.size, weight: spec.weight, design: spec.design)
    }
}

extension View {
    /// Sets this text in one of the type roles. Pass `color` to override the role's ink.
    public func sbText(_ role: SBTextRole, color: Color? = nil) -> some View {
        modifier(SBTextModifier(role: role, color: color))
    }
}

struct SBTextModifier: ViewModifier {
    let role: SBTextRole
    let color: Color?
    @ScaledMetric private var scale: CGFloat

    init(role: SBTextRole, color: Color?) {
        self.role = role
        self.color = color
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: role.spec.style ?? .body)
    }

    func body(content: Content) -> some View {
        let spec = role.spec
        let size = spec.size * (spec.style == nil ? 1 : scale)
        return content
            .font(.system(size: size, weight: spec.weight, design: spec.design))
            .tracking(size * spec.tracking)
            .textCase(spec.uppercase ? .uppercase : nil)
            .foregroundStyle(color ?? spec.color)
    }
}

/// Small mono caps: "STILL WANT · 9", "1 / 4".
public struct SBLabel: View {
    private let text: String
    private let dim: Bool

    public init(_ text: String, dim: Bool = true) {
        self.text = text
        self.dim = dim
    }

    public var body: some View {
        Text(text)
            .sbText(dim ? .labelDim : .label)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

// MARK: - Icons

/// The app's line icons: one 24-unit drawing each, stroked at 1.6.
public enum SBIcon: Hashable, Sendable {
    case back, x, check, arrow, plus, home, bookmark, spark, search, filter, ticket, cal, map, send, sliders, more, stack, bracket
    /// An SF Symbol, for the few glyphs the set doesn't have.
    case system(String)

    /// The set's icon for an SF Symbol name, so callers that speak in symbols keep working.
    public init(systemName: String) {
        switch systemName {
        case "chevron.left": self = .back
        case "xmark": self = .x
        case "checkmark": self = .check
        case "arrow.right", "arrow.up.right": self = .arrow
        case "plus": self = .plus
        case "ellipsis": self = .more
        case "calendar", "calendar.badge.plus": self = .cal
        case "map": self = .map
        case "paperplane", "square.and.arrow.up": self = .send
        case "magnifyingglass": self = .search
        case "slider.horizontal.3": self = .sliders
        case "square.stack": self = .stack
        case "bookmark": self = .bookmark
        default: self = .system(systemName)
        }
    }
}

public struct SBIconView: View {
    private let icon: SBIcon
    private let size: CGFloat

    public init(_ icon: SBIcon, size: CGFloat = 20) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        Group {
            switch icon {
            case .system(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.78, weight: .light))
            case .more:
                SBIconShape(icon: icon).fill()
            default:
                SBIconShape(icon: icon)
                    .stroke(style: StrokeStyle(lineWidth: 1.6 * size / 24, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SBIconShape: Shape {
    let icon: SBIcon

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func m(_ x: CGFloat, _ y: CGFloat) { p.move(to: CGPoint(x: x, y: y)) }
        func l(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: CGPoint(x: x, y: y)) }
        func q(_ x: CGFloat, _ y: CGFloat, _ cx: CGFloat, _ cy: CGFloat) { p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy)) }
        switch icon {
        case .back: m(15, 5); l(8, 12); l(15, 19)
        case .x: m(6, 6); l(18, 18); m(18, 6); l(6, 18)
        case .check: m(5, 12.5); l(9.5, 17); l(19, 7.5)
        case .arrow: m(5, 12); l(19, 12); m(13, 6); l(19, 12); l(13, 18)
        case .plus: m(12, 5); l(12, 19); m(5, 12); l(19, 12)
        case .home:
            m(4, 11); l(12, 4); l(20, 11); l(20, 19.5); q(18.5, 21, 20, 21); l(15, 21); l(15, 15); l(9, 15); l(9, 21); l(5.5, 21); q(4, 19.5, 4, 21)
            p.closeSubpath()
        case .bookmark: m(7, 4); l(17, 4); l(17, 20); l(12, 16); l(7, 20); p.closeSubpath()
        case .spark:
            m(12, 3); l(13.8, 8.4); l(19, 10); l(13.8, 11.6); l(12, 17); l(10.2, 11.6); l(5, 10); l(10.2, 8.4); p.closeSubpath()
            m(19, 16); l(19.7, 18); l(21.7, 18.7); l(19.7, 19.4); l(19, 21.4); l(18.3, 19.4); l(16.3, 18.7); l(18.3, 18); p.closeSubpath()
        case .search: p.addEllipse(in: CGRect(x: 5, y: 5, width: 12, height: 12)); m(20, 20); l(15.5, 15.5)
        case .filter: m(4, 6); l(20, 6); l(14, 13.5); l(14, 19); l(10, 20.5); l(10, 13.5); p.closeSubpath()
        case .ticket:
            m(4, 7); l(20, 7); l(20, 10); q(20, 14, 17.6, 12); l(20, 17); l(4, 17); l(4, 14); q(4, 10, 6.4, 12); p.closeSubpath()
            m(14, 7); l(14, 17)
        case .cal:
            p.addRoundedRect(in: CGRect(x: 4, y: 5, width: 16, height: 15), cornerSize: CGSize(width: 3, height: 3))
            m(4, 10); l(20, 10); m(9, 3); l(9, 7); m(15, 3); l(15, 7)
        case .map: m(9, 4); l(4, 6); l(4, 20); l(9, 18); l(15, 20); l(20, 18); l(20, 4); l(15, 6); p.closeSubpath(); m(9, 4); l(9, 18); m(15, 6); l(15, 20)
        case .send: m(20, 4); l(10, 14); m(20, 4); l(14, 20); l(10, 14); l(4, 10); p.closeSubpath()
        case .sliders:
            m(4, 7); l(14, 7); m(18, 7); l(20, 7); m(4, 17); l(8, 17); m(12, 17); l(20, 17)
            p.addEllipse(in: CGRect(x: 14, y: 5, width: 4, height: 4)); p.addEllipse(in: CGRect(x: 8, y: 15, width: 4, height: 4))
        case .more:
            for x in [5.0, 12.0, 19.0] { p.addEllipse(in: CGRect(x: x - 1.6, y: 10.4, width: 3.2, height: 3.2)) }
        case .stack:
            p.addRoundedRect(in: CGRect(x: 5, y: 9, width: 14, height: 11), cornerSize: CGSize(width: 3, height: 3))
            m(7, 6); l(17, 6); m(9, 3); l(15, 3)
        case .bracket: m(8, 4); l(5, 4); l(5, 20); l(8, 20); m(16, 4); l(19, 4); l(19, 20); l(16, 20)
        case .system: break
        }
        let scale = min(rect.width, rect.height) / 24
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
    }
}

// MARK: - Buttons

/// A round action button: back, close, more, search.
public struct SBCircleButton: View {
    private let icon: SBIcon
    private let label: String
    private let size: CGFloat
    private let onGlass: Bool
    private let action: () -> Void

    public init(_ icon: SBIcon, label: String, size: CGFloat = 44, onGlass: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.size = size
        self.onGlass = onGlass
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            SBCircleLabel(icon, size: size, onGlass: onGlass)
        }
        .buttonStyle(SBPressStyle())
        .accessibilityLabel(Text(label))
    }
}

/// The circle button's look, for a `Menu` label.
public struct SBCircleLabel: View {
    private let icon: SBIcon
    private let size: CGFloat
    private let onGlass: Bool

    public init(_ icon: SBIcon, size: CGFloat = 44, onGlass: Bool = false) {
        self.icon = icon
        self.size = size
        self.onGlass = onGlass
    }

    public var body: some View {
        SBIconView(icon, size: size >= 44 ? 20 : 18)
            .foregroundStyle(SBColor.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(onGlass ? SBColor.warm(0.10) : SBColor.surface2))
            .overlay(Circle().strokeBorder(onGlass ? SBColor.line : Color.clear, lineWidth: 1))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
    }
}

/// A choosable round chip, like a day of the week. On, it's warm white.
public struct SBChipCircle: View {
    private let text: String
    private let isOn: Bool
    private let size: CGFloat
    private let action: () -> Void

    public init(_ text: String, isOn: Bool, size: CGFloat = 44, action: @escaping () -> Void) {
        self.text = text
        self.isOn = isOn
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? SBColor.ground : SBColor.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(isOn ? SBColor.accent : Color.clear))
                .overlay(Circle().strokeBorder(isOn ? SBColor.accent : SBColor.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(SBPressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The forward action: a dark capsule, the label on the left, a warm white circle with the glyph
/// on the right.
public struct SBCTA: View {
    private let title: String
    private let icon: SBIcon
    private let onLight: Bool
    private let action: () -> Void

    public init(_ title: String, icon: SBIcon = .arrow, onLight: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.onLight = onLight
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            SBCTALabel(title, icon: icon, onLight: onLight)
        }
        .buttonStyle(SBPressStyle())
        .accessibilityLabel(Text(title))
    }
}

/// The CTA's look, for wrapping in other controls (a `ShareLink`, a `PhotosPicker`).
public struct SBCTALabel: View {
    private let title: String
    private let icon: SBIcon
    private let onLight: Bool
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .subheadline) private var textSize: CGFloat = 15

    public init(_ title: String, icon: SBIcon = .arrow, onLight: Bool = false) {
        self.title = title
        self.icon = icon
        self.onLight = onLight
    }

    public var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: textSize))
                .foregroundStyle(SBColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 24)
            SBIconView(icon, size: 18)
                .foregroundStyle(SBColor.ground)
                .frame(width: 36, height: 36)
                .background(Circle().fill(SBColor.accent))
        }
        .frame(minWidth: 197 - 32)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, 24)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background {
            if onLight {
                Capsule().fill(SBColor.inkOnLight)
            } else {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(SBColor.ctaFill)
                    Capsule().strokeBorder(SBColor.warm(0.08), lineWidth: 1)
                }
            }
        }
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// One pill in a decision row. The primary one is warm white.
public struct SBSegButton: View {
    private let title: String
    private let icon: SBIcon?
    private let isPrimary: Bool
    private let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var textSize: CGFloat = 15

    public init(_ title: String, icon: SBIcon? = nil, isPrimary: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isPrimary = isPrimary
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    SBIconView(icon, size: 18)
                }
                Text(title)
                    .font(.system(size: textSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isPrimary ? SBColor.ground : SBColor.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
            .background(SBPillBackground(isPrimary: isPrimary))
            .contentShape(Capsule())
        }
        .buttonStyle(SBPressStyle())
    }
}

/// A pill's fill: translucent warm glass, or warm white for the primary one.
struct SBPillBackground: View {
    let isPrimary: Bool

    var body: some View {
        ZStack {
            if isPrimary {
                Capsule().fill(SBColor.accent)
            } else {
                Capsule().fill(SBColor.warm(0.07))
                Capsule().strokeBorder(SBColor.warm(0.14), lineWidth: 1)
                Capsule()
                    .strokeBorder(LinearGradient(colors: [SBColor.warm(0.10), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2)), lineWidth: 1)
            }
        }
    }
}

/// A glass row of pills.
public struct SBSegmentRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        SBFlexRow(spacing: 4) {
            content
        }
        .padding(5)
        .background {
            ZStack {
                Capsule().fill(SBColor.warm(0.05))
                Capsule().strokeBorder(SBColor.warm(0.12), lineWidth: 1)
            }
        }
    }
}

/// Deciding on an item, always in the same order: Drop · Still want · Done.
public struct SBDecisionRow: View {
    private let onDrop: () -> Void
    private let onKeep: () -> Void
    private let onDone: () -> Void

    public init(onDrop: @escaping () -> Void, onKeep: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.onDrop = onDrop
        self.onKeep = onKeep
        self.onDone = onDone
    }

    public var body: some View {
        SBSegmentRow {
            SBSegButton("Drop", icon: .x, action: onDrop)
            SBSegButton("Still want", icon: .bookmark, isPrimary: true, action: onKeep)
            SBSegButton("Done", icon: .check, action: onDone)
        }
    }
}

/// Lays children out in a row like CSS `flex: 1 1 auto`: each gets its ideal width plus an equal
/// share of what's left.
public struct SBFlexRow: Layout {
    private let spacing: CGFloat

    public init(spacing: CGFloat = 4) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let ideal = sizes.map(\.width).reduce(0, +) + gaps
        return CGSize(width: proposal.width ?? ideal, height: sizes.map(\.height).max() ?? 0)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let share = (bounds.width - ideals.reduce(0, +) - gaps) / CGFloat(subviews.count)
        var x = bounds.minX
        for index in subviews.indices {
            let width = max(0, ideals[index] + share)
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}

/// An action on one thing (calendar, maps, send, done): an outlined pill lit in the item's kind,
/// in mono caps. With `fill`, a solid gradient pill instead.
public struct SBScenarioButton: View {
    private let title: String
    private let icon: SBIcon
    private let color: Color
    private let fill: LinearGradient?
    private let height: CGFloat
    private let action: () -> Void

    public init(_ title: String, icon: SBIcon, color: Color, fill: LinearGradient? = nil, height: CGFloat = 56, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.fill = fill
        self.height = height
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            SBScenarioLabel(title, icon: icon, color: color, fill: fill, height: height)
        }
        .buttonStyle(SBPressStyle())
        .accessibilityLabel(Text(title))
    }
}

/// The scenario pill's look, for wrapping in other controls (a `ShareLink`).
public struct SBScenarioLabel: View {
    private let title: String
    private let icon: SBIcon
    private let color: Color
    private let fill: LinearGradient?
    private let height: CGFloat

    public init(_ title: String, icon: SBIcon, color: Color, fill: LinearGradient? = nil, height: CGFloat = 56) {
        self.title = title
        self.icon = icon
        self.color = color
        self.fill = fill
        self.height = height
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: SBRadius.scenario, style: .continuous)
        HStack(spacing: 10) {
            SBIconView(icon, size: 18)
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(fill == nil ? SBColor.ink : SBColor.ground)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background {
            if let fill {
                shape.fill(fill)
            } else {
                shape.strokeBorder(color, lineWidth: 1.5)
                    .shadow(color: color.opacity(0.3), radius: 5)
            }
        }
        .contentShape(shape)
    }
}

/// A gentle press: a little smaller and dimmer while held.
public struct SBPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(SBMotion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Surfaces

/// A soft blurred light: the glow that lives inside tiles and behind objects.
public struct SBLight: View {
    private let color: Color
    private let width: CGFloat
    private let height: CGFloat
    private let opacity: Double
    private let blur: CGFloat

    public init(_ color: Color, width: CGFloat, height: CGFloat, opacity: Double = 0.6, blur: CGFloat = 36) {
        self.color = color
        self.width = width
        self.height = height
        self.opacity = opacity
        self.blur = blur
    }

    public var body: some View {
        Ellipse()
            .fill(color)
            .frame(width: width, height: height)
            .blur(radius: blur)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A neutral tile holding one light in a corner.
public struct SBTile<Content: View>: View {
    private let radius: CGFloat
    private let light: Color?
    private let lightAlignment: Alignment
    private let content: Content

    public init(radius: CGFloat = SBRadius.tile, light: Color? = nil, lightAlignment: Alignment = .bottomTrailing, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.light = light
        self.lightAlignment = lightAlignment
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: lightAlignment) {
                    SBColor.surface
                    if let light {
                        SBLight(light, width: 170, height: 150)
                            .offset(x: lightAlignment.horizontal == .trailing ? 70 : -70, y: lightAlignment.vertical == .bottom ? 80 : -80)
                    }
                }
                .clipShape(shape)
            }
            .compositingGroup()
    }
}

/// A Saved tile: the kind's light blooming down from the top edge, the name low down.
public struct SBKindTile: View {
    private let kind: SBKind
    private let title: String
    private let count: Int
    private let height: CGFloat

    public init(kind: SBKind, title: String, count: Int, height: CGFloat = 200) {
        self.kind = kind
        self.title = title
        self.count = count
        self.height = height
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: SBRadius.tile, style: .continuous)
        ZStack(alignment: .bottom) {
            SBColor.surface
            GeometryReader { proxy in
                Ellipse()
                    .fill(RadialGradient(stops: [
                        .init(color: kind.core, location: 0),
                        .init(color: kind.core, location: 0.4),
                        .init(color: kind.deep, location: 0.75),
                        .init(color: kind.deep.opacity(0), location: 1),
                    ], center: .center, startRadius: 0, endRadius: proxy.size.width * 1.1))
                    .frame(width: proxy.size.width * 2.2, height: 200)
                    .position(x: proxy.size.width / 2, y: 0)
                    .blur(radius: 36)
            }
            (Text(title.uppercased()) + Text("  ·  \(count)").foregroundColor(SBColor.ink2))
                .sbText(.label)
                .padding(.bottom, 26)
        }
        .frame(height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(kind.core.opacity(0.35), lineWidth: 1))
        .compositingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title), \(count)"))
    }
}

/// The light card behind the setup scan and the recap time: the ramp's light colour with a deep
/// well of light in the middle.
public struct SBRampCard<Content: View>: View {
    private let wellCenter: UnitPoint
    private let content: Content

    public init(wellCenter: UnitPoint = UnitPoint(x: 0.5, y: 0.42), @ViewBuilder content: () -> Content) {
        self.wellCenter = wellCenter
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: SBRadius.objectCard, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    ZStack {
                        SBRamp.card
                        Ellipse()
                            .fill(RadialGradient(stops: [
                                .init(color: SBColor.ground, location: 0),
                                .init(color: SBColor.ground, location: 0.3),
                                .init(color: Color(hex: 0x31150B), location: 0.45),
                                .init(color: SBRamp.r1, location: 0.58),
                                .init(color: Color(hex: 0xB44622), location: 0.74),
                                .init(color: Color(hex: 0xF5966B), location: 0.88),
                                .init(color: SBRamp.card, location: 1),
                            ], center: .center, startRadius: 0, endRadius: proxy.size.width * 0.55))
                            .frame(width: proxy.size.width * 1.1, height: proxy.size.width * 1.2)
                            .position(x: proxy.size.width * wellCenter.x, y: proxy.size.height * wellCenter.y)
                            .blur(radius: 6)
                    }
                }
                .clipShape(shape)
            }
            .shadow(color: .black.opacity(0.4), radius: 30, y: 30)
    }
}

/// The ground every screen sits on: warm near-black with fine grain.
public struct SBGround: View {
    public init() {}

    public var body: some View {
        ZStack {
            SBColor.ground
            GrainOverlay(amount: 0.12)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Puts this screen on the warm, moving light (see `SBLiveBackground`), set by the screen's
    /// state. Pushed screens need it, so the screen below doesn't show through during the push.
    public func sbScreen(_ ambience: SBAmbience = .standard) -> some View {
        background(SBLiveBackground(ambience))
    }
}

// MARK: - Chrome

/// The header on opened screens: a round back (or close) button and a title, with an optional
/// control on the right.
public struct SBNavHeader<Trailing: View>: View {
    private let title: String?
    private let leading: SBIcon
    private let leadingLabel: String
    private let onLeading: () -> Void
    private let trailing: Trailing

    public init(
        title: String? = nil,
        leading: SBIcon = .back,
        leadingLabel: String = "Back",
        onLeading: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading
        self.leadingLabel = leadingLabel
        self.onLeading = onLeading
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 14) {
            SBCircleButton(leading, label: leadingLabel, action: onLeading)
            if let title {
                Text(title)
                    .sbText(.nav)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, SBSpace.gutter)
        .padding(.top, SBSpace.headerTop)
        .frame(minHeight: 44)
    }
}

extension SBNavHeader where Trailing == EmptyView {
    public init(title: String? = nil, leading: SBIcon = .back, leadingLabel: String = "Back", onLeading: @escaping () -> Void) {
        self.init(title: title, leading: leading, leadingLabel: leadingLabel, onLeading: onLeading) { EmptyView() }
    }
}

/// A main screen's title: large and centred, with an optional round control either side.
public struct SBLargeHeader<Leading: View, Trailing: View>: View {
    private let title: String
    private let leading: Leading
    private let trailing: Trailing

    public init(_ title: String, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        ZStack {
            Text(title)
                .sbText(.large)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
            HStack {
                leading
                Spacer(minLength: 0)
                trailing
            }
        }
        .padding(.horizontal, SBSpace.gutter)
        .padding(.top, SBSpace.headerTop)
        .frame(minHeight: 44)
    }
}

extension SBLargeHeader where Leading == EmptyView, Trailing == EmptyView {
    public init(_ title: String) {
        self.init(title, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// Story progress on Reveal cards: viewed bars warm white, the current one part-filled.
public struct SBStoryBars: View {
    private let count: Int
    private let current: Int

    public init(count: Int, current: Int) {
        self.count = count
        self.current = current
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(count, 0), id: \.self) { index in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SBColor.warm(0.28))
                        if index < current {
                            Capsule().fill(SBColor.accent)
                        } else if index == current {
                            Capsule().fill(SBColor.accent).frame(width: proxy.size.width * 0.4)
                        }
                    }
                }
                .frame(height: 2)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Card \(current + 1) of \(count)"))
    }
}

/// The app's mark: brackets, like a screenshot's frame, and the name.
public struct SBMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 15) {
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 7) {
            SBIconView(.bracket, size: size * 1.2)
            Text("Screenshot Brain")
                .font(.system(size: size, weight: .semibold))
                .tracking(-0.01 * size)
        }
        .foregroundStyle(SBColor.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Screenshot Brain"))
    }
}

/// A short confirmation, in a glass capsule.
public struct SBToast: View {
    private let text: String
    private let icon: SBIcon?

    public init(_ text: String, icon: SBIcon? = .check) {
        self.text = text
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let icon {
                SBIconView(icon, size: 12)
                    .foregroundStyle(SBColor.ground)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(SBColor.accent))
            }
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(SBColor.ink)
                .lineLimit(2)
        }
        .padding(.leading, icon == nil ? 18 : 12)
        .padding(.trailing, 18)
        .frame(minHeight: 44)
        .sbGlass(in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A text chip: an outlined capsule in mono caps, with an optional glyph. `onImage` sits on
/// imagery.
public struct SBChip: View {
    public enum Style: Sendable {
        case outline
        case onImage
    }

    private let title: String
    private let icon: SBIcon?
    private let style: Style

    public init(_ title: String, icon: SBIcon? = nil, style: Style = .outline) {
        self.title = title
        self.icon = icon
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .sbText(style == .outline ? .labelDim : .label)
                .lineLimit(1)
            if let icon {
                SBIconView(icon, size: 12)
                    .foregroundStyle(style == .outline ? SBColor.ink2 : SBColor.ink)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background {
            switch style {
            case .outline:
                Capsule().strokeBorder(SBColor.line, lineWidth: 1)
            case .onImage:
                ZStack {
                    Capsule().fill(SBColor.chipOnImage)
                    Capsule().strokeBorder(SBColor.warm(0.14), lineWidth: 1)
                }
            }
        }
        .contentShape(Capsule())
        .padding(.vertical, 6)
    }
}

// MARK: - Layout helpers

extension EnvironmentValues {
    /// How much of the bottom of the screen is covered by chrome (the tab bar), so bottom controls
    /// can sit above it.
    public var sbBottomClearance: CGFloat {
        get { self[SBBottomClearanceKey.self] }
        set { self[SBBottomClearanceKey.self] = newValue }
    }
}

private struct SBBottomClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

/// The recap card's panel: a folder with a raised tab on the left of its top edge.
public struct SBFolderPanelShape: InsettableShape {
    private let bottomRadius: CGFloat
    private var inset: CGFloat = 0

    public init(bottomRadius: CGFloat = SBRadius.objectCard) {
        self.bottomRadius = bottomRadius
    }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let w = r.width, h = r.height, s = w / 328, radius = min(bottomRadius, h / 2)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x, y: r.minY + y) }
        var p = Path()
        p.move(to: pt(0, 16))
        p.addQuadCurve(to: pt(16, 0), control: pt(0, 0))
        p.addLine(to: pt(190 * s, 0))
        p.addQuadCurve(to: pt(213 * s, 10), control: pt(207 * s, 0))
        p.addLine(to: pt(230 * s, 24))
        p.addQuadCurve(to: pt(240 * s, 28), control: pt(234 * s, 28))
        p.addLine(to: pt(w - 15, 28))
        p.addQuadCurve(to: pt(w, 43), control: pt(w, 28))
        p.addLine(to: pt(w, h - radius))
        p.addQuadCurve(to: pt(w - radius, h), control: pt(w, h))
        p.addLine(to: pt(radius, h))
        p.addQuadCurve(to: pt(0, h - radius), control: pt(0, h))
        p.closeSubpath()
        return p
    }

    public func inset(by amount: CGFloat) -> SBFolderPanelShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}
