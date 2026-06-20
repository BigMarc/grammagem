import Foundation

/// Built-in Writing Modes (system-prompt presets for the local LLM).
///
/// Per the spec's soft-deterrent note (§5), the *free* mode (`polish`) ships in
/// the public repo, while the paid modes' fully-tuned prompts ship only in the
/// signed release. Here we include readable baseline prompts for all of them;
/// swap the paid ones for your tuned versions in the release build.
enum ModeRegistry {
    static let polish = WritingMode(
        id: "polish",
        name: "Polish",
        systemPrompt: """
        You are a careful copy editor. Lightly clean up the user's text: fix \
        grammar, spelling, and punctuation, and improve clarity, while \
        preserving their voice, meaning, and formatting. Return only the \
        revised text with no commentary.
        """,
        isPaid: false,
        lengthCap: nil,
        autoFormat: "Preserve original"
    )

    static let email = WritingMode(
        id: "email",
        name: "Email",
        systemPrompt: """
        Rewrite the user's text as a professional, warm email. Keep it concise \
        and natural — never robotic. Add a brief greeting and sign-off only if \
        appropriate. Return only the email body.
        """,
        isPaid: true,
        lengthCap: 120,
        autoFormat: "Greeting + sign-off"
    )

    static let post = WritingMode(
        id: "post",
        name: "Post",
        systemPrompt: """
        Rewrite the user's text as a punchy social post. Short lines, strong \
        verbs, no fluff. Keep it under 280 characters. Return only the post.
        """,
        isPaid: true,
        lengthCap: 280,
        autoFormat: "Line breaks, no fluff"
    )

    static let slack = WritingMode(
        id: "slack",
        name: "Team Chat",
        systemPrompt: """
        Rewrite the user's text as a friendly, direct team-chat message. \
        Conversational, lowercase is fine, get to the point. Return only the message.
        """,
        isPaid: true,
        lengthCap: 60,
        autoFormat: "Inline, casual"
    )

    static let academic = WritingMode(
        id: "academic",
        name: "Academic",
        systemPrompt: """
        Rewrite the user's text in a formal, academic register. Hedge claims \
        appropriately, prefer precise vocabulary, and use complete sentences. \
        Return only the revised text.
        """,
        isPaid: true,
        lengthCap: nil,
        autoFormat: "Formal, hedged"
    )

    static let code = WritingMode(
        id: "code",
        name: "Code Comment",
        systemPrompt: """
        Rewrite the user's text as a clear code comment / commit message: \
        imperative mood, concise, technical. Return only the comment text.
        """,
        isPaid: true,
        lengthCap: nil,
        autoFormat: "Imperative, terse"
    )

    /// Everything the app knows about.
    static let all: [WritingMode] = [polish, email, post, slack, academic, code]

    /// Modes a given tier may use (free: Polish only; paid: all + custom).
    static func available(for tier: Tier) -> [WritingMode] {
        tier.isPaid ? all : all.filter { !$0.isPaid }
    }

    static func mode(id: String) -> WritingMode? {
        all.first { $0.id == id }
    }

    /// Map a frontmost-app bundle identifier to the Mode it should auto-apply.
    /// Used by the App-Aware feature (paid).
    static func mode(forBundleID bundleID: String) -> WritingMode? {
        switch bundleID {
        case "com.apple.mail": return email
        case "com.tinyspeck.slackmacgap": return slack
        case "com.apple.MobileSMS": return slack
        case "notion.id", "com.notion.desktop": return polish
        case "com.microsoft.VSCode", "com.apple.dt.Xcode": return code
        case "com.apple.Safari", "com.google.Chrome": return polish
        default: return nil
        }
    }
}
