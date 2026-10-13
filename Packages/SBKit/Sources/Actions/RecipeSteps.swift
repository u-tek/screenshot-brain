import Foundation

/// The method of a recipe screenshot, one step at a time, for cook mode.
public enum RecipeSteps {
    /// "1.", "1)", "Step 1", "Step 1:". A bare "2 cups" is an ingredient, not a step, so a plain
    /// number needs its dot or bracket, and that must be followed by a space ("1.5 cups" isn't one).
    private static let numbered = try! NSRegularExpression(
        pattern: #"^\s*(?:step\s*\d{1,2}\s*[.):\-–]?|\d{1,2}\s*[.)])(?=\s|$)\s*(.*)$"#,
        options: [.caseInsensitive]
    )

    /// Headings that start the steps.
    private static let methodHeadings: Set<String> = ["method", "directions", "instructions", "steps"]

    /// Headings that end them.
    private static let otherHeadings: Set<String> = [
        "ingredients", "notes", "note", "tips", "tip", "nutrition", "preparation", "prep", "serves", "serving", "to serve", "storage", "equipment",
    ]

    /// The steps in a recipe's text, in order. Empty when there are none to find.
    ///
    /// Numbered lines are steps ("1.", "1)", "Step 1"). Without any, the lines under a "Method",
    /// "Directions", "Instructions" or "Steps" heading are, up to the next heading. A line that
    /// wraps onto the next one is joined back into one step.
    public static func steps(in text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let fromNumbers = numberedSteps(in: lines)
        return fromNumbers.isEmpty ? headedSteps(in: lines) : fromNumbers
    }

    private static func numberedSteps(in lines: [String]) -> [String] {
        var steps: [String] = []
        // Whether the last step can still take a wrapped line.
        var isOpen = false
        for line in lines {
            if let body = numberedBody(of: line) {
                steps.append(body)
                isOpen = true
            } else if line.isEmpty || heading(of: line) != nil {
                isOpen = false
            } else if isOpen, !steps.isEmpty {
                steps[steps.count - 1] = join(steps[steps.count - 1], line)
            }
        }
        return steps.filter { step in step.contains { $0.isLetter } }
    }

    private static func headedSteps(in lines: [String]) -> [String] {
        var steps: [String] = []
        var inSection = false
        var isOpen = false
        for line in lines {
            if let name = heading(of: line) {
                inSection = methodHeadings.contains(name)
                isOpen = false
                continue
            }
            guard inSection else { continue }
            if line.isEmpty {
                isOpen = false
                continue
            }
            let text = stripBullet(line)
            // A line joins the one before it when that didn't finish its sentence.
            if isOpen, let last = steps.last, !endsSentence(last) {
                steps[steps.count - 1] = join(last, text)
            } else {
                steps.append(text)
            }
            isOpen = true
        }
        return steps.filter { step in step.contains { $0.isLetter } }
    }

    /// The text after "1." or "Step 1", if the line starts a numbered step.
    private static func numberedBody(of line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = numbered.firstMatch(in: line, range: range), let body = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[body]).trimmingCharacters(in: .whitespaces)
    }

    /// The lowercased name when the line is one of the headings, with or without a colon.
    private static func heading(of line: String) -> String? {
        let name = line.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ":*#_-• ").union(.whitespaces))
        guard methodHeadings.contains(name) || otherHeadings.contains(name) else { return nil }
        return name
    }

    private static func stripBullet(_ line: String) -> String {
        guard let first = line.first, "-•*".contains(first) else { return line }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return true }
        return ".!?:".contains(last)
    }

    private static func join(_ first: String, _ second: String) -> String {
        first.isEmpty ? second : "\(first) \(second)"
    }
}
