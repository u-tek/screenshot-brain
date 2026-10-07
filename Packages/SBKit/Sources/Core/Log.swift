import Foundation
import os

/// Unified logging categories. Never log screenshot text or entity values; log counts and identifiers only.
public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ScreenshotBrain"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let scan = Logger(subsystem: subsystem, category: "scan")
    public static let safety = Logger(subsystem: subsystem, category: "safety")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
}
