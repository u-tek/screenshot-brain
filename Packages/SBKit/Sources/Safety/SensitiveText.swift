import Foundation

/// Text that must never leave the app's private surfaces: card numbers, bank details,
/// passwords and one-time codes. Items containing any of it go to Reference and are never
/// eligible for the widget or anything shareable.
public enum SensitiveTextKind: String, CaseIterable, Sendable {
    case cardNumber
    case bankDetails
    case password
    case oneTimeCode
}

public enum SensitiveTextDetector {
    public static func findings(in text: String) -> Set<SensitiveTextKind> {
        var found: Set<SensitiveTextKind> = []
        if containsCardNumber(text) { found.insert(.cardNumber) }
        if containsBankDetails(text) { found.insert(.bankDetails) }
        if containsPassword(text) { found.insert(.password) }
        if containsOneTimeCode(text) { found.insert(.oneTimeCode) }
        return found
    }

    // MARK: Card numbers

    /// 13 to 19 digits, optionally grouped with spaces or dashes, that pass the Luhn check.
    static func containsCardNumber(_ text: String) -> Bool {
        for match in matches(of: #"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#, in: text) {
            let digits = match.filter(\.isNumber)
            if (13...19).contains(digits.count), luhnValid(digits) {
                return true
            }
        }
        return false
    }

    public static func luhnValid(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, values.count >= 2 else { return false }
        var sum = 0
        for (index, value) in values.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return sum % 10 == 0
    }

    // MARK: Bank details

    static func containsBankDetails(_ text: String) -> Bool {
        let lowered = text.lowercased()
        // Australian BSB with an account number nearby.
        if lowered.contains("bsb"), !matches(of: #"\b\d{3}[- ]?\d{3}\b"#, in: text).isEmpty {
            return true
        }
        // UK sort code.
        if lowered.contains("sort code"), !matches(of: #"\b\d{2}-\d{2}-\d{2}\b"#, in: text).isEmpty {
            return true
        }
        // US routing number.
        if lowered.contains("routing"), !matches(of: #"\b\d{9}\b"#, in: text).isEmpty {
            return true
        }
        // An explicit account number label followed by digits.
        if !matches(of: #"(?i)(account|acct|acc)\s*(no\.?|number|#)?\s*:?\s*\d{6,}"#, in: text).isEmpty {
            return true
        }
        // IBAN.
        if !matches(of: #"\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}\s?[A-Z0-9]{1,4}\b"#, in: text).isEmpty,
           lowered.contains("iban") {
            return true
        }
        return false
    }

    // MARK: Passwords and codes

    static func containsPassword(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["password", "passcode", "passwort", "contraseña", "mot de passe"].contains { lowered.contains($0) }
    }

    static func containsOneTimeCode(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let phrases = ["verification code", "one-time", "one time code", "otp", "security code",
                       "your code is", "login code", "sign-in code", "authentication code", "2fa"]
        // Whole words: "otp" is in "hotpot".
        let named = phrases.contains { phrase in
            lowered.range(of: "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b", options: .regularExpression) != nil
        }
        guard named else { return false }
        return !matches(of: #"\b\d{4,8}\b"#, in: text).isEmpty
    }

    // MARK: Helpers

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            Range(result.range, in: text).map { String(text[$0]) }
        }
    }
}
