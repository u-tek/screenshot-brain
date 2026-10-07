import Core
import DesignSystem
import Media
import ScanEngine
import Store
import SwiftUI

/// Debug-only tools: the scan benchmark, the accuracy harness and the design lab.
struct DebugMenu: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Scan benchmark (last 60)") { BenchmarkView() }
                NavigationLink("Was this right? (accuracy)") { AccuracyView() }
                NavigationLink("Design lab") { DesignLabView() }
            }
            .navigationTitle("Debug")
        }
    }
}

// MARK: - Benchmark

@MainActor
final class BenchmarkModel: ObservableObject {
    enum Phase {
        case idle
        case running(read: Int, total: Int)
        case finished(seconds: Double, count: Int, stages: [(stage: ScanStage, seconds: Double, count: Int)])
        case failed(String)
    }

    /// The brief's target: the first 60 screenshots fully processed in 15 seconds on an iPhone 8.
    static let target: Double = 15
    @Published var phase: Phase = .idle

    func run() async {
        let access = await ScreenshotLibrary.requestAccess()
        guard access == .full || access == .limited else {
            phase = .failed("Photo access is needed to run the benchmark.")
            return
        }
        do {
            // A throwaway database and thumbnail folder, so the benchmark never touches real data.
            let database = try AppDatabase.inMemory()
            let thumbnails = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark-thumbnails", isDirectory: true)
            try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
            let pipeline = ScanPipeline(database: database, thumbnailDirectory: thumbnails)
            let timer = StageTimer()

            let start = Date()
            let latest = Array(ScreenshotLibrary().discover(since: nil).prefix(60))
            try database.recordDiscovered(latest)
            phase = .running(read: 0, total: latest.count)
            try await pipeline.readPending(limit: 60, timer: timer) { progress in
                Task { @MainActor in
                    self.phase = .running(read: progress.read, total: progress.total)
                }
            }
            phase = .finished(seconds: Date().timeIntervalSince(start), count: latest.count, stages: timer.summary)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct BenchmarkView: View {
    @StateObject private var model = BenchmarkModel()

    var body: some View {
        List {
            Section {
                Button("Run on the last 60 screenshots") {
                    Task { await model.run() }
                }
            } footer: {
                Text("Target: 60 screenshots in \(Int(BenchmarkModel.target)) seconds or less on an iPhone 8 running iOS 16.")
            }
            switch model.phase {
            case .idle:
                EmptyView()
            case .running(let read, let total):
                Section("Running") {
                    Text("\(read) of \(total) read").font(SBFont.mono(13))
                }
            case .finished(let seconds, let count, let stages):
                Section("Result") {
                    row("screenshots", "\(count)")
                    row("total", String(format: "%.2f s", seconds))
                    row("verdict", seconds <= BenchmarkModel.target ? "PASS" : "OVER TARGET")
                }
                Section("Time per stage (summed across workers)") {
                    ForEach(stages, id: \.stage) { entry in
                        row(entry.stage.rawValue, String(format: "%.2f s  · %d", entry.seconds, entry.count))
                    }
                }
            case .failed(let message):
                Section("Failed") { Text(message) }
            }
        }
        .navigationTitle("Benchmark")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased()).font(SBFont.mono(12)).foregroundStyle(SBColor.inkSecondary)
            Spacer()
            Text(value).font(SBFont.mono(13))
        }
    }
}

// MARK: - Accuracy harness

@MainActor
final class AccuracyModel: ObservableObject {
    @Published var items: [ScreenshotItem] = []
    @Published var records: [AccuracyRecord] = []
    private var answered: Set<String> = []

    /// A category ships only at this accuracy or better with test users.
    static let shippingBar = 0.95

    func load() {
        guard let database = AppServices.shared?.database else { return }
        let deck = (try? database.triageDeck(limit: 200)) ?? []
        items = deck.map(\.item).filter { !answered.contains($0.id) }
        records = (try? database.accuracyRecords()) ?? []
    }

    func answer(_ item: ScreenshotItem, correct: Bool) {
        guard let database = AppServices.shared?.database else { return }
        try? database.recordAccuracy(category: item.category, correct: correct)
        answered.insert(item.id)
        load()
    }
}

struct AccuracyView: View {
    @StateObject private var model = AccuracyModel()

    var body: some View {
        List {
            Section("By category (ships at \(Int(AccuracyModel.shippingBar * 100))%)") {
                ForEach(model.records, id: \.category) { record in
                    HStack {
                        Text(record.category.rawValue.uppercased()).font(SBFont.mono(12))
                        Spacer()
                        Text(record.accuracy.map { String(format: "%.0f%%", $0 * 100) } ?? "–").font(SBFont.mono(12))
                        Text("\(record.correct)/\(record.correct + record.wrong)").font(SBFont.mono(12)).foregroundStyle(SBColor.inkSecondary)
                    }
                }
            }
            Section("Was this right?") {
                ForEach(model.items) { item in
                    HStack(spacing: 12) {
                        AssetImage(item.assetLocalID, maxPixelSize: 240)
                            .frame(width: 56, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.category.rawValue.capitalized).font(SBFont.body(15, weight: .semibold))
                            Text(item.title ?? "Untitled").font(SBFont.body(13)).foregroundStyle(SBColor.inkSecondary).lineLimit(2)
                            Text(String(format: "confidence %.2f", item.confidence)).font(SBFont.mono(11)).foregroundStyle(SBColor.inkSecondary)
                        }
                        Spacer()
                        Button { model.answer(item, correct: false) } label: { DropMark(size: 36) }.buttonStyle(.plain)
                        Button { model.answer(item, correct: true) } label: { DoneMark(size: 36) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Accuracy")
        .onAppear { model.load() }
    }
}
