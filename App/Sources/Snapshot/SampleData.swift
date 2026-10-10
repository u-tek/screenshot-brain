import Core
import Foundation
import Store

/// Made-up items for design snapshots and previews. Never shown in the app itself.
enum SampleData {
    /// 9:41, like the status bar in the snapshots.
    static let now = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()

    static func item(
        _ category: ItemCategory,
        _ title: String,
        daysAgo: Double,
        dueIn: Double? = nil,
        state: ItemState = .stillWant,
        entities: [DetectedEntity] = []
    ) -> ScreenshotItem {
        ScreenshotItem(
            id: "sample-\(title)",
            assetLocalID: "sample-\(title)",
            createdAt: now.addingTimeInterval(-daysAgo * 86_400),
            category: category,
            confidence: 0.92,
            entities: entities,
            state: state,
            stateChangedAt: now.addingTimeInterval(-daysAgo * 86_400),
            title: title,
            dueDate: dueIn.map { evening(inDays: $0) },
            processedAt: now
        )
    }

    /// 8pm, some days from now.
    static func evening(inDays days: Double) -> Date {
        let day = now.addingTimeInterval(days * 86_400)
        return Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: day) ?? day
    }

    static let gig = item(.event, "Mallrat at the Enmore", daysAgo: 12, dueIn: 3, entities: [
        DetectedEntity(kind: .date, text: "8pm", date: evening(inDays: 3)),
        DetectedEntity(kind: .address, text: "118-132 Enmore Rd, Newtown"),
        DetectedEntity(kind: .price, text: "$69.90"),
    ])

    static let comingUp = [
        gig,
        item(.event, "Night market, Chinatown", daysAgo: 5, dueIn: 4),
        item(.product, "XT-6 sale ends", daysAgo: 9, dueIn: 6),
    ]

    static let shelves: [(ItemCategory, [ScreenshotItem])] = [
        (.place, (0..<9).map { item(.place, "Place \($0)", daysAgo: 40 - Double($0)) }),
        (.product, (0..<6).map { item(.product, "Product \($0)", daysAgo: 21 - Double($0)) }),
        (.recipe, (0..<4).map { item(.recipe, "Recipe \($0)", daysAgo: 60 - Double($0)) }),
        (.event, [gig, comingUp[1]]),
    ]

    static let filed: [(ItemCategory, [ScreenshotItem])] = [
        (.message, (0..<42).map { item(.message, "Chat \($0)", daysAgo: Double($0), state: .reference) }),
        (.post, (0..<18).map { item(.post, "Post \($0)", daysAgo: Double($0), state: .reference) }),
        (.reference, (0..<11).map { item(.reference, "Receipt \($0)", daysAgo: Double($0), state: .reference) }),
        (.other, (0..<7).map { item(.other, "Photo \($0)", daysAgo: Double($0), state: .reference) }),
    ]
}
