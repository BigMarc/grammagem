import SwiftUI
import AppKit

/// A floating panel that lists every on-screen text area with grammar/spelling
/// issues, shows the offending text with the errors highlighted, and offers
/// one-click fixes (per issue, per field, or everything).
struct LiveCheckView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var monitor: LiveMonitor

    init() {
        _monitor = ObservedObject(wrappedValue: AppState.shared.liveMonitor)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if monitor.fields.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(monitor.fields) { field in
                            FieldCard(field: field)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(GG.emerald)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ScoreRing(score: monitor.writingScore)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary).font(.headline)
                    Text(contextLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { monitor.refreshSoon() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Re-scan now")
                if monitor.issueCount > 0 {
                    Button { app.fixAllDetected() } label: {
                        Label("Fix everything", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if monitor.issueCount > 0 {
                HStack(spacing: 8) {
                    ForEach(IssueBucket.allCases) { bucket in
                        if let n = monitor.bucketCounts[bucket], n > 0 {
                            BucketChip(bucket: bucket, count: n)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
    }

    private var summary: String {
        let issues = monitor.issueCount
        if issues == 0 { return "Looks clean" }
        return "\(issues) issue\(issues == 1 ? "" : "s") across \(monitor.fields.count) text area\(monitor.fields.count == 1 ? "" : "s")"
    }

    private var contextLine: String {
        monitor.activeAppName.isEmpty
            ? "Checking text areas on screen"
            : "In \(monitor.activeAppName) · \(monitor.scannedCount) text area\(monitor.scannedCount == 1 ? "" : "s") checked"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 42)).foregroundStyle(GG.emerald)
            Text("Looks clean").font(.title3.weight(.semibold))
            Text("No grammar or spelling issues in the text on screen right now.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// One detected text area: highlighted text + its individual issues.
private struct FieldCard: View {
    @EnvironmentObject private var app: AppState
    let field: DetectedField

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: field.isFocused ? "cursorarrow.rays" : "text.cursor")
                    .foregroundStyle(field.isFocused ? GG.emerald : .secondary)
                Text(field.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(field.roleName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(field.suggestions.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(GG.gold.opacity(0.2), in: Capsule())
                    .foregroundStyle(GG.gold)
            }

            Text(highlighted(field.text, field.suggestions))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 6) {
                ForEach(field.suggestions) { s in
                    HStack(spacing: 8) {
                        Circle().fill(color(for: s.kind)).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.message).font(.caption)
                            if s.replacement != s.original && !s.replacement.isEmpty {
                                Text("“\(s.original)” → “\(s.replacement)”")
                                    .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        if s.kind == .spelling {
                            Button { app.addWordToDictionary(s.original) } label: {
                                Image(systemName: "book.closed")
                            }
                            .controlSize(.small).buttonStyle(.borderless)
                            .help("Add “\(s.original)” to your dictionary")
                        }
                        Button { app.dismissSuggestion(s, in: field) } label: {
                            Image(systemName: "xmark")
                        }
                        .controlSize(.small).buttonStyle(.borderless)
                        .help("Dismiss this suggestion")
                        if s.replacement != s.original && !s.replacement.isEmpty {
                            Button("Apply") { app.applySuggestion(s, in: field) }
                                .controlSize(.small).buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button { app.fixDetectedField(field) } label: {
                    Label("Fix this field", systemImage: "checkmark.circle")
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
    }

    private func color(for kind: GrammarKind) -> Color {
        switch kind {
        case .spelling: return .red
        case .grammar, .punctuation: return .orange
        default: return GG.gold
        }
    }

    fileprivate static func color(for bucket: IssueBucket) -> Color {
        switch bucket {
        case .correctness: return .red
        case .clarity: return .blue
        case .polish: return GG.gold
        }
    }

    /// Build an attributed string with each issue span tinted.
    private func highlighted(_ text: String, _ suggestions: [Suggestion]) -> AttributedString {
        let ns = text as NSString
        let sorted = suggestions.sorted { $0.location < $1.location }
        var result = AttributedString()
        var cursor = 0
        for s in sorted {
            let loc = s.location, len = s.length
            guard loc >= cursor, len > 0, loc + len <= ns.length else { continue }
            if loc > cursor {
                result += AttributedString(ns.substring(with: NSRange(location: cursor, length: loc - cursor)))
            }
            var run = AttributedString(ns.substring(with: NSRange(location: loc, length: len)))
            let tint: Color = s.kind == .spelling ? .red : .orange
            run.backgroundColor = tint.opacity(0.18)
            run.foregroundColor = tint
            run.underlineStyle = .single
            result += run
            cursor = loc + len
        }
        if cursor < ns.length {
            result += AttributedString(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }
        return result
    }
}

/// A compact 0–100 cleanliness gauge. Green when clean, amber/orange as issues
/// pile up — a meter the user can watch climb as they accept fixes.
private struct ScoreRing: View {
    let score: Int
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: score)
            Text("\(score)").font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .frame(width: 44, height: 44)
        .help("Writing score for the text on screen")
    }

    private var color: Color {
        score >= 90 ? GG.emerald : (score >= 70 ? GG.gold : .orange)
    }
}

/// A tappable-looking count chip per issue bucket (Correctness / Clarity / Polish).
private struct BucketChip: View {
    let bucket: IssueBucket
    let count: Int
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(FieldCard.color(for: bucket)).frame(width: 7, height: 7)
            Text("\(bucket.title) \(count)").font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(FieldCard.color(for: bucket).opacity(0.12), in: Capsule())
    }
}
