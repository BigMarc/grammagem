import Foundation
import os

/// Thin wrapper over `os.Logger`. Privacy-first: we never log user text.
enum Log {
    private static let subsystem = AppConfig.bundleIdentifier

    static let system = Logger(subsystem: subsystem, category: "system")
    static let grammar = Logger(subsystem: subsystem, category: "grammar")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let licensing = Logger(subsystem: subsystem, category: "licensing")
    static let app = Logger(subsystem: subsystem, category: "app")
}
