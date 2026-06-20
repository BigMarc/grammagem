import SwiftUI

/// Brand accents for the app UI (mirrors the website CI).
enum GG {
    static let emerald = Color(red: 0x0E / 255, green: 0x7C / 255, blue: 0x5A / 255)
    static let gold = Color(red: 0xC9 / 255, green: 0xA2 / 255, blue: 0x4B / 255)
}

/// Sections of the management window.
enum MainSection: String, CaseIterable, Identifiable {
    case dashboard, devices, license
    case modes, dictionary, snippets
    case shortcuts, model, privacy, exclusions, general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .devices: return "Devices"
        case .license: return "License"
        case .modes: return "Writing Modes"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .shortcuts: return "Shortcuts"
        case .model: return "AI Model"
        case .privacy: return "Privacy"
        case .exclusions: return "Page Blocker"
        case .general: return "General"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .devices: return "laptopcomputer"
        case .license: return "key"
        case .modes: return "slider.horizontal.3"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .shortcuts: return "command"
        case .model: return "cpu"
        case .privacy: return "lock.shield"
        case .exclusions: return "hand.raised"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }

    /// Sidebar groups, in order.
    static let groups: [(String, [MainSection])] = [
        ("Overview", [.dashboard]),
        ("Account", [.devices, .license]),
        ("Writing", [.modes, .dictionary, .snippets]),
        ("App", [.shortcuts, .model, .privacy, .exclusions, .general]),
        ("", [.about]),
    ]
}

/// The full GrammarGem management window: a clean sidebar + detail layout.
struct MainWindowView: View {
    @State private var selection: MainSection?

    init(initialSection: MainSection = .dashboard) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(MainSection.groups, id: \.0) { group, items in
                    Section(group) {
                        ForEach(items) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 198, ideal: 216, max: 260)
            .listStyle(.sidebar)
        } detail: {
            detail(for: selection ?? .dashboard)
        }
        .tint(GG.emerald)
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder
    private func detail(for section: MainSection) -> some View {
        switch section {
        case .dashboard: DashboardView()
        case .devices: DevicesView()
        case .license: LicenseView()
        case .modes: WritingModesView()
        case .dictionary: DictionaryView()
        case .snippets: SnippetsView()
        case .shortcuts: ShortcutsView()
        case .model: ModelView()
        case .privacy: PrivacyView()
        case .exclusions: ExclusionsView()
        case .general: GeneralView()
        case .about: AboutView()
        }
    }
}

// MARK: - Reusable layout

/// A scrollable detail page with a title/subtitle header and a max content width.
struct DetailScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.largeTitle.bold())
                    if let subtitle {
                        Text(subtitle).font(.body).foregroundStyle(.secondary)
                    }
                }
                content
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }
}

/// A soft card container used throughout the window.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

/// A small labelled metric tile.
struct StatTile: View {
    let value: String
    let label: String
    var systemImage: String? = nil
    var tint: Color = .primary

    var body: some View {
        Card {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(tint)
                }
                Text(value).font(.system(.title, design: .rounded).weight(.semibold)).foregroundStyle(tint)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A locked-feature badge used to surface upgrade triggers cleanly.
struct UpgradeBadge: View {
    var body: some View {
        Label("Lifetime", systemImage: "lock.fill")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(GG.gold.opacity(0.18), in: Capsule())
            .foregroundStyle(GG.gold)
    }
}
