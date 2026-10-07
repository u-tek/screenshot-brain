import Core
import Testing
@testable import Safety

@Suite struct SensitiveTextTests {
    @Test(arguments: ["4111111111111111", "4242424242424242", "5555555555554444", "378282246310005"])
    func luhnAcceptsTestCards(number: String) {
        #expect(SensitiveTextDetector.luhnValid(number))
    }

    @Test(arguments: ["4111111111111112", "1234567812345678", "0000000000000001"])
    func luhnRejectsOtherNumbers(number: String) {
        #expect(!SensitiveTextDetector.luhnValid(number))
    }

    @Test func findsGroupedCardNumbers() {
        #expect(SensitiveTextDetector.findings(in: "Card 4111 1111 1111 1111 exp 04/29").contains(.cardNumber))
        #expect(SensitiveTextDetector.findings(in: "Card 4111-1111-1111-1111").contains(.cardNumber))
    }

    @Test func ignoresNumbersThatFailLuhn() {
        #expect(!SensitiveTextDetector.findings(in: "Order 1234 5678 1234 5678 shipped").contains(.cardNumber))
        #expect(!SensitiveTextDetector.findings(in: "Call 0412 345 678").contains(.cardNumber))
    }

    @Test func findsBankDetails() {
        #expect(SensitiveTextDetector.findings(in: "BSB 062-000\nAccount 12345678").contains(.bankDetails))
        #expect(SensitiveTextDetector.findings(in: "Sort code 12-34-56").contains(.bankDetails))
        #expect(SensitiveTextDetector.findings(in: "Account number: 0012345678").contains(.bankDetails))
    }

    @Test func findsPasswordsAndCodes() {
        #expect(SensitiveTextDetector.findings(in: "Wi-Fi password: coffee123").contains(.password))
        #expect(SensitiveTextDetector.findings(in: "Your verification code is 482913").contains(.oneTimeCode))
        #expect(!SensitiveTextDetector.findings(in: "Verify your email").contains(.oneTimeCode))
    }

    @Test func ordinaryTextIsNotSensitive() {
        let text = "That gig at the Enmore\nFri 14 Nov, doors 7pm\nTickets $59.90"
        #expect(SensitiveTextDetector.findings(in: text).isEmpty)
    }
}

@Suite struct SafeToDisplayTests {
    private let clean = SafetyVerdict(isNSFWFlagged: false, sensitiveText: [])

    @Test func confidentIntentionsAreSafe() {
        for category in [ItemCategory.place, .event, .product, .recipe] {
            #expect(Safety.isSafeToDisplay(category: category, confidence: 0.9, verdict: clean))
        }
    }

    @Test func referenceOtherAndLowConfidenceAreNot() {
        #expect(!Safety.isSafeToDisplay(category: .reference, confidence: 0.99, verdict: clean))
        #expect(!Safety.isSafeToDisplay(category: .other, confidence: 0.99, verdict: clean))
        #expect(!Safety.isSafeToDisplay(category: .event, confidence: 0.6, verdict: clean))
    }

    @Test func flaggedOrSensitiveItemsAreNever() {
        let nsfw = SafetyVerdict(isNSFWFlagged: true, sensitiveText: [])
        let sensitive = SafetyVerdict(isNSFWFlagged: false, sensitiveText: [.cardNumber])
        #expect(!Safety.isSafeToDisplay(category: .product, confidence: 0.99, verdict: nsfw))
        #expect(!Safety.isSafeToDisplay(category: .product, confidence: 0.99, verdict: sensitive))
    }
}
