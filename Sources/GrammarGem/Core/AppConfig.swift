import Foundation

/// Compile-time configuration. The Lemon Squeezy identifiers are hard-coded so
/// the licensing layer can *hard-verify* that a key belongs to GrammarGem (and to
/// the claimed tier) rather than to some other Lemon Squeezy product.
/// TODO(real-integration): replace every `TODO_*` value with your real IDs.
enum AppConfig {
    static let appName = "GrammarGem"
    static let bundleIdentifier = "com.foundergem.grammargem" // TODO(real-integration)
    static let supportEmail = "support@grammargem.com" // TODO(real-integration)
    static let modelPortalURL = URL(string: "https://www.grammargem.com/license")! // TODO
    static let websiteURL = URL(string: "https://www.grammargem.com")!
    static let appVersion = "0.1.0"

    // Legal entity (shown in About / legal).
    static let companyName = "FounderGem LLC"
    static let companyAddress = "1309 Coffeen Avenue STE 1200, Sheridan, WY 82801, USA"
    static let copyright = "© 2026 FounderGem LLC"

    /// Lemon Squeezy License API (app talks to it directly — no server of ours).
    enum LemonSqueezy {
        static let apiBase = URL(string: "https://api.lemonsqueezy.com/v1")!
        static let expectedStoreID = "TODO_STORE_ID"
        static let expectedProductID = "TODO_PRODUCT_ID"
        /// One variant per tier; the variant's activation limit is the device cap.
        static let variantID: [Tier: String] = [
            .solo: "TODO_SOLO_VARIANT_ID",
            .personal: "TODO_PERSONAL_VARIANT_ID",
            .studio: "TODO_STUDIO_VARIANT_ID",
        ]
    }

    /// Local LLM weights, pulled from Hugging Face on first run (never bundled).
    enum Model {
        static let defaultRepo = "mlx-community/Qwen2.5-3B-Instruct-4bit" // Apache-2.0
        static let largeRepo = "mlx-community/Qwen2.5-7B-Instruct-4bit"   // optional, paid tiers
        static let huggingFaceBase = "https://huggingface.co"
    }

    /// The cross-platform Layer-2 backend: a locally-running Ollama server. Used
    /// when MLX isn't available (Windows/Linux) or when the user opts in. Inference
    /// stays on-device — Ollama runs the model on the user's own machine.
    enum Ollama {
        static let baseURL = URL(string: "http://127.0.0.1:11434")!
        static let defaultModel = "qwen2.5:3b" // matches the MLX default model family
    }

    /// Loopback engine server for the browser extension (off by default; see
    /// `LocalEngineServer`). Exposes Harper + the local LLM to the extension over
    /// 127.0.0.1 with a per-install token — no cloud round-trip.
    enum LocalServer {
        static let port: UInt16 = 47800
        static let tokenKey = "GrammarGem.localServerToken"
        static let enableKey = "GrammarGem.enableLocalServer"
    }

    /// Free-tier limits + license validation cadence (see spec §5/§6).
    enum Limits {
        static let freeDailyAIActions = 10
        static let freeDictionaryCap = 25
        static let validationIntervalDays = 7
        static let offlineGraceDays = 30
    }

    /// Default global hotkey: ⌘; (Carbon key code 41, Carbon cmdKey mask 256).
    /// Stored as raw integers here to keep this file free of the Carbon import.
    enum Hotkey {
        static let defaultKeyCode: UInt32 = 41   // kVK_ANSI_Semicolon
        static let defaultModifiers: UInt32 = 256 // cmdKey
        // A second hotkey opens the "Ask" popover (default ⌘' = key 39).
        static let askKeyCode: UInt32 = 39       // kVK_ANSI_Quote
        static let askModifiers: UInt32 = 256
    }
}
