import Core
import Foundation
import Store

/// A triage decision. Right is still want, up is done, left is drop.
public enum TriageDecision: String, CaseIterable, Sendable {
    case keep
    case done
    case drop

    public var state: ItemState {
        switch self {
        case .keep: .stillWant
        case .done: .done
        case .drop: .dropped
        }
    }
}

/// What came of a run through the deck.
public struct TriageTally: Hashable, Sendable {
    public var kept = 0
    public var done = 0
    public var dropped = 0

    public init(kept: Int = 0, done: Int = 0, dropped: Int = 0) {
        self.kept = kept
        self.done = done
        self.dropped = dropped
    }

    mutating func count(_ decision: TriageDecision, by amount: Int) {
        switch decision {
        case .keep: kept += amount
        case .done: done += amount
        case .drop: dropped += amount
        }
    }
}

/// The deck: the cards, how far through they are, and an undo for the last decision.
@MainActor
public final class TriageModel: ObservableObject {
    @Published public private(set) var cards: [TriageCard]
    @Published public private(set) var position = 0
    @Published public private(set) var tally = TriageTally()
    private var history: [(decision: TriageDecision, previous: [ScreenshotItem])] = []
    private let database: AppDatabase?
    private let onDecision: (TriageDecision) -> Void

    public init(cards: [TriageCard], database: AppDatabase?, onDecision: @escaping (TriageDecision) -> Void = { _ in }) {
        self.cards = cards
        self.database = database
        self.onDecision = onDecision
    }

    public var current: TriageCard? {
        cards.indices.contains(position) ? cards[position] : nil
    }

    /// The top card and the two behind it.
    public var visible: [TriageCard] {
        Array(cards.dropFirst(position).prefix(3))
    }

    public var isFinished: Bool {
        position >= cards.count
    }

    public var canUndo: Bool {
        !history.isEmpty
    }

    public func decide(_ decision: TriageDecision) {
        guard let card = current else { return }
        let previous = (try? database?.decide(decision.state, forItem: card.item.id)) ?? [card.item]
        history.append((decision, previous))
        tally.count(decision, by: 1)
        position += 1
        onDecision(decision)
    }

    public func undo() {
        guard let last = history.popLast() else { return }
        try? database?.undoDecision(restoring: last.previous)
        tally.count(last.decision, by: -1)
        position = max(position - 1, 0)
    }
}

extension TriageModel {
    /// Cards for previews and design snapshots: no images, just each category's light.
    public static func sampleCards() -> [TriageCard] {
        let now = Date()
        // 8pm, some days from now, like a gig.
        func evening(inDays days: Double) -> Date {
            let day = now.addingTimeInterval(days * 86_400)
            return Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: day) ?? day
        }
        func card(_ category: ItemCategory, _ title: String, daysAgo: Double, due: Double? = nil, group: Int = 1) -> TriageCard {
            let item = ScreenshotItem(
                assetLocalID: "sample-\(title)",
                createdAt: now.addingTimeInterval(-daysAgo * 86_400),
                category: category,
                confidence: 0.9,
                isSafeToDisplay: false,
                title: title,
                dueDate: due.map(evening(inDays:))
            )
            return TriageCard(item: item, groupSize: group)
        }
        return [
            card(.event, "Mallrat at the Enmore", daysAgo: 12, due: 3, group: 2),
            card(.place, "Ramen Ikkyu", daysAgo: 23),
            card(.product, "Salomon XT-6", daysAgo: 4),
            card(.recipe, "Crispy chilli noodles", daysAgo: 40),
        ]
    }
}
