import Foundation
import Testing
@testable import Core

@Suite struct AppConfigurationTests {
    @Test func unsetBuildSettingsReadAsNil() {
        let configuration = AppConfiguration(infoDictionary: [
            "SBAppGroupIdentifier": "group.com.example.screenshotbrain",
            "SBCloudKitContainerIdentifier": "  ",
            "SBTelemetryDeckAppID": "",
        ])
        #expect(configuration.appGroupIdentifier == "group.com.example.screenshotbrain")
        #expect(configuration.cloudKitContainerIdentifier == nil)
        #expect(configuration.telemetryDeckAppID == nil)
    }
}

@Suite struct AnalyticsTests {
    @Test func sendsTheEventNameAndIntegerCountsOnly() {
        let recorder = Recorder()
        let analytics = Analytics { name, parameters in recorder.record(name, parameters) }

        analytics.track(.revealCompleted, counts: ["cards": 8])

        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.name == "reveal.completed")
        #expect(recorder.events.first?.parameters == ["cards": "8"])
    }

    @Test func eventNamesAreUnique() {
        let names = AnalyticsEvent.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
    }
}

@Suite struct DomainTests {
    @Test func onlyThingsToDoAreDisplayable() {
        let displayable = ItemCategory.allCases.filter(\.isDisplayableIntention)
        #expect(displayable == [.place, .event, .product, .recipe, .watch, .listen, .read, .travel])
    }

    @Test func chatsPostsReferenceAndOtherAreNotThingsToDo() {
        for category in [ItemCategory.message, .post, .reference, .other] {
            #expect(!category.isActionable)
            #expect(!category.isIntention)
        }
    }

    @Test func onboardingStepsAreOrdered() {
        #expect(OnboardingStep.pitch < .signIn)
        #expect(OnboardingStep.reveal < .triage)
        #expect(OnboardingStep.allCases.sorted() == OnboardingStep.allCases)
    }

    @Test(arguments: [
        (0, DayPeriod.lateNight),
        (4, DayPeriod.lateNight),
        (5, DayPeriod.morning),
        (12, DayPeriod.afternoon),
        (17, DayPeriod.evening),
        (22, DayPeriod.lateNight),
    ])
    func dayPeriodFromHour(hour: Int, expected: DayPeriod) {
        #expect(DayPeriod(hour: hour) == expected)
    }

    @Test func datesKnowWhetherTheyNamedATime() {
        #expect(DetectedEntity(kind: .date, text: "Sat 14 Oct 8pm").namesATime)
        #expect(DetectedEntity(kind: .date, text: "19:30").namesATime)
        #expect(DetectedEntity(kind: .date, text: "Fri, 7.30 p.m.").namesATime)
        #expect(!DetectedEntity(kind: .date, text: "Sat 14 Oct").namesATime)
        #expect(!DetectedEntity(kind: .date, text: "14/10/2026").namesATime)
        #expect(!DetectedEntity(kind: .address, text: "8pm Lane").namesATime)
    }
}

private final class Recorder: @unchecked Sendable {
    struct Event: Equatable {
        var name: String
        var parameters: [String: String]
    }

    private let lock = NSLock()
    private var storage: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ name: String, _ parameters: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(Event(name: name, parameters: parameters))
    }
}
