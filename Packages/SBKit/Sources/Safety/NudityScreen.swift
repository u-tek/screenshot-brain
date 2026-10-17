import CoreGraphics
import Foundation
@preconcurrency import NSFWDetector
#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis
#endif
import UIKit

/// Decides whether a screenshot contains nudity. Runs on every screenshot before anything can be
/// displayed; a flagged item never appears anywhere.
public protocol NudityScreening: Sendable {
    /// True when the image must be treated as nudity. An image that couldn't be screened counts
    /// as flagged: fail closed.
    func isFlagged(_ image: CGImage) async -> Bool
    /// Like `isFlagged`, but nil when the screen couldn't decide (a detector error). Callers
    /// that can try again later should leave the screenshot unread rather than guess.
    func isFlaggedIfKnown(_ image: CGImage) async -> Bool?
}

extension NudityScreening {
    public func isFlaggedIfKnown(_ image: CGImage) async -> Bool? {
        await isFlagged(image)
    }
}

/// On-device screening: LOVOO's NSFWDetector (a 17 kB Core ML model, BSD-3-Clause), plus Apple's
/// Sensitive Content Analysis where the user has sensitive content warnings turned on.
///
/// Sensitive Content Analysis only runs for users who have opted in, so it's an extra signal and
/// never the only one. The thresholds lean strict: a false positive hides a screenshot from the
/// app's surfaces; a false negative could show nudity on a home screen.
public final class OnDeviceNudityScreen: NudityScreening, @unchecked Sendable {
    /// Flag at or above this NSFWDetector confidence. The model's own guidance is 0.9 for a
    /// permissive feed; screenshots that might reach a home screen get a much stricter bar.
    public static let threshold: Float = 0.5

    private let lock = NSLock()
    private var detector: NSFWDetector?

    public init() {}

    public func isFlagged(_ image: CGImage) async -> Bool {
        await isFlaggedIfKnown(image) ?? true
    }

    public func isFlaggedIfKnown(_ image: CGImage) async -> Bool? {
        let confidence = await nsfwConfidence(image)
        if let confidence, confidence >= Self.threshold {
            return true
        }
        let analysis = await sensitiveContentAnalysisFlags(image)
        if analysis == true {
            return true
        }
        // Either screen failing means nothing was ruled out.
        if confidence == nil || analysis == nil {
            return nil
        }
        return false
    }

    private func nsfwConfidence(_ image: CGImage) async -> Float? {
        let detector = sharedDetector()
        let uiImage = UIImage(cgImage: image)
        return await withCheckedContinuation { continuation in
            detector.check(image: uiImage) { result in
                switch result {
                case .success(let confidence):
                    continuation.resume(returning: confidence)
                case .error:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func sharedDetector() -> NSFWDetector {
        lock.lock()
        defer { lock.unlock() }
        if let detector { return detector }
        let created = NSFWDetector.shared
        detector = created
        return created
    }

    /// Nil when the analysis was on but failed. Off (the user hasn't opted in) is a plain no.
    private func sensitiveContentAnalysisFlags(_ image: CGImage) async -> Bool? {
        #if canImport(SensitiveContentAnalysis)
        if #available(iOS 17.0, *) {
            let analyzer = SCSensitivityAnalyzer()
            guard analyzer.analysisPolicy != .disabled else { return false }
            do {
                return try await analyzer.analyzeImage(image).isSensitive
            } catch {
                return nil
            }
        }
        #endif
        return false
    }
}
