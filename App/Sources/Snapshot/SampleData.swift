import Core
import Foundation
import Store

/// Made-up items for design snapshots and previews. Never shown in the app itself.
enum SampleData {
    static let now = Date()

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
            dueDate: dueIn.map { now.addingTimeInterval($0 * 86_400) },
            processedAt: now
        )
    }

    static let gig = item(.event, "Mallrat at the Enmore", daysAgo: 12, dueIn: 3, entities: [
        DetectedEntity(kind: .date, text: "Fri 8pm", date: now.addingTimeInterval(3 * 86_400)),
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
}
