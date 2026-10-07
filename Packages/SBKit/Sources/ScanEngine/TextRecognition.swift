import CoreGraphics
import Foundation
import Vision

/// One line of text read from a screenshot.
public struct TextLine: Hashable, Sendable {
    public var text: String
    /// Normalised bounding box, origin bottom-left (Vision's convention).
    public var box: CGRect
    public var confidence: Float

    public init(text: String, box: CGRect, confidence: Float = 1) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

/// Everything read from one screenshot.
public struct RecognizedText: Hashable, Sendable {
    public var lines: [TextLine]
    /// Barcodes and QR codes found in the image.
    public var codeCount: Int
    /// Vision's labels for the whole image, used only when there's little text.
    public var imageLabels: [String]

    public init(lines: [TextLine], codeCount: Int = 0, imageLabels: [String] = []) {
        self.lines = lines
        self.codeCount = codeCount
        self.imageLabels = imageLabels
    }

    /// Lines top to bottom, joined with newlines.
    public var fullText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    public var wordCount: Int {
        lines.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    /// Lowercased words, for similarity between near-duplicates.
    public var words: Set<String> {
        Set(fullText.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
    }
}

/// Vision text recognition, tuned for speed: `.fast`, no language correction.
public struct TextRecognizer: Sendable {
    /// Below this many words, Vision's image classifier is asked for labels as a fallback signal.
    public var littleTextWordCount = 8

    public init() {}

    public func recognize(_ image: CGImage) throws -> RecognizedText {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        let barcodeRequest = VNDetectBarcodesRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([textRequest, barcodeRequest])

        let observations = textRequest.results ?? []
        let lines: [TextLine] = observations
            .compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return TextLine(text: candidate.string, box: observation.boundingBox, confidence: candidate.confidence)
            }
            // Top to bottom, then left to right.
            .sorted { lhs, rhs in
                abs(lhs.box.midY - rhs.box.midY) > 0.01 ? lhs.box.midY > rhs.box.midY : lhs.box.minX < rhs.box.minX
            }
        let codeCount = barcodeRequest.results?.count ?? 0

        var recognized = RecognizedText(lines: lines, codeCount: codeCount)
        if recognized.wordCount < littleTextWordCount {
            recognized.imageLabels = (try? labels(for: handler)) ?? []
        }
        return recognized
    }

    private func labels(for handler: VNImageRequestHandler) throws -> [String] {
        let request = VNClassifyImageRequest()
        try handler.perform([request])
        return (request.results ?? [])
            .filter { $0.confidence >= 0.3 }
            .prefix(8)
            .map(\.identifier)
    }
}
