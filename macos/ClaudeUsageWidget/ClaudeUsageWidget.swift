import WidgetKit
import SwiftUI

// MARK: - Data Models

struct ClaudeUsageData {
    let displayName: String
    let email: String
    let plan: String
    let totalTokensIn: Int
    let totalTokensOut: Int
    let totalSessions: Int
    let totalProjects: Int
    let recentPrompts: [RecentPrompt]
}

struct RecentPrompt {
    let text: String
    let timeAgo: String
}

// MARK: - Data Provider

struct ClaudeUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudeUsageEntry {
        ClaudeUsageEntry(
            date: Date(),
            data: ClaudeUsageData(
                displayName: "User",
                email: "user@example.com",
                plan: "Pro",
                totalTokensIn: 14_500_000,
                totalTokensOut: 48_000,
                totalSessions: 38,
                totalProjects: 5,
                recentPrompts: [
                    RecentPrompt(text: "Create a menu bar app", timeAgo: "2h ago")
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeUsageEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeUsageEntry>) -> Void) {
        let data = loadUsageData()
        let entry = ClaudeUsageEntry(date: Date(), data: data)
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadUsageData() -> ClaudeUsageData {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Load account info
        var displayName = "Unknown"
        var email = "Unknown"
        var plan = "Unknown"

        let configPath = "\(home)/.claude.json"
        if let configData = FileManager.default.contents(atPath: configPath),
           let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
           let oauth = config["oauthAccount"] as? [String: Any] {
            displayName = oauth["displayName"] as? String ?? "Unknown"
            email = oauth["emailAddress"] as? String ?? "Unknown"
            let billingType = oauth["billingType"] as? String ?? "unknown"
            switch billingType {
            case "stripe_subscription": plan = "Pro"
            case "enterprise": plan = "Enterprise"
            case "free": plan = "Free"
            default: plan = billingType
            }
        }

        // Load project stats
        var totalTokensIn = 0
        var totalTokensOut = 0
        var totalSessions = 0
        var totalProjects = 0

        let projectsPath = "\(home)/.claude/projects/"
        if let projectDirs = try? FileManager.default.contentsOfDirectory(atPath: projectsPath) {
            for dir in projectDirs {
                let dirPath = "\(projectsPath)\(dir)"
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }

                var hasSession = false
                if let files = try? FileManager.default.contentsOfDirectory(atPath: dirPath) {
                    for file in files where file.hasSuffix(".jsonl") {
                        hasSession = true
                        totalSessions += 1
                        let filePath = "\(dirPath)/\(file)"
                        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                            let lines = content.components(separatedBy: "\n")
                            for line in lines {
                                guard let lineData = line.data(using: .utf8),
                                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                                if json["type"] as? String == "assistant",
                                   let message = json["message"] as? [String: Any],
                                   let usage = message["usage"] as? [String: Any] {
                                    totalTokensIn += usage["input_tokens"] as? Int ?? 0
                                    totalTokensIn += usage["cache_read_input_tokens"] as? Int ?? 0
                                    totalTokensOut += usage["output_tokens"] as? Int ?? 0
                                }
                            }
                        }
                    }
                }
                if hasSession { totalProjects += 1 }
            }
        }

        // Load recent prompts
        var recentPrompts: [RecentPrompt] = []
        let historyPath = "\(home)/.claude/history.jsonl"
        if let content = try? String(contentsOfFile: historyPath, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n").reversed()
            for line in lines {
                guard recentPrompts.count < 3 else { break }
                guard let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let display = json["display"] as? String, !display.isEmpty,
                      let timestamp = json["timestamp"] as? Double else { continue }
                let date = Date(timeIntervalSince1970: timestamp / 1000)
                recentPrompts.append(RecentPrompt(text: display, timeAgo: date.timeAgoString()))
            }
        }

        return ClaudeUsageData(
            displayName: displayName,
            email: email,
            plan: plan,
            totalTokensIn: totalTokensIn,
            totalTokensOut: totalTokensOut,
            totalSessions: totalSessions,
            totalProjects: totalProjects,
            recentPrompts: recentPrompts
        )
    }
}

// MARK: - Timeline Entry

struct ClaudeUsageEntry: TimelineEntry {
    let date: Date
    let data: ClaudeUsageData
}

// MARK: - Helpers

extension Date {
    func timeAgoString() -> String {
        let diff = Date().timeIntervalSince(self)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        if diff < 604800 { return "\(Int(diff / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}

extension Int {
    var formattedTokens: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.1fK", Double(self) / 1_000)
        }
        return "\(self)"
    }
}

// MARK: - Colors

extension Color {
    static let widgetOrange = Color(red: 0.91, green: 0.47, blue: 0.18)
    static let widgetOrangeLight = Color(red: 0.94, green: 0.60, blue: 0.35)
    static let widgetBg = Color(red: 0.05, green: 0.05, blue: 0.05)
    static let widgetSurface = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let widgetBarBg = Color(red: 0.16, green: 0.16, blue: 0.16)
}

// MARK: - Widget View

struct ClaudeWidgetView: View {
    let entry: ClaudeUsageEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemLarge:
            largeView
        default:
            largeView
        }
    }

    var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image("MenuBarIcon")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude Usage")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(entry.data.email)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Text(entry.data.plan)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.widgetOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.widgetOrange.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Stats Grid
            HStack(spacing: 8) {
                statCard(icon: "arrow.down", label: "Tokens In", value: entry.data.totalTokensIn.formattedTokens)
                statCard(icon: "arrow.up", label: "Tokens Out", value: entry.data.totalTokensOut.formattedTokens)
                statCard(icon: "bubble.left", label: "Sessions", value: "\(entry.data.totalSessions)")
                statCard(icon: "folder", label: "Projects", value: "\(entry.data.totalProjects)")
            }

            // Recent Activity
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent Activity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.widgetOrange)

                if entry.data.recentPrompts.isEmpty {
                    Text("No recent activity")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                } else {
                    ForEach(Array(entry.data.recentPrompts.enumerated()), id: \.offset) { _, prompt in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(Color.widgetOrange.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(prompt.text)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(2)
                                Text(prompt.timeAgo)
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.widgetSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func statCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.widgetOrange)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.widgetSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Widget Definition

struct ClaudeUsageWidget: Widget {
    let kind: String = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageProvider()) { entry in
            ClaudeWidgetView(entry: entry)
                .containerBackground(Color.widgetBg, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Track your Claude API usage at a glance.")
        .supportedFamilies([.systemLarge])
    }
}
