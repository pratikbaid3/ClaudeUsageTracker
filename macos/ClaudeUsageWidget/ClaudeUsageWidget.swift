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
    let totalMessages: Int
    let tokensToday: Int
    let sessionsToday: Int
    let topProjectName: String
    let topProjectTokens: Int
    let rl5hUtil: Double  // -1 = below threshold, 0..1 = percentage
    let rl5hReset: Int
    let rl7dUtil: Double
    let rl7dReset: Int
}

// MARK: - Data Provider

struct ClaudeUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudeUsageEntry {
        ClaudeUsageEntry(date: Date(), data: ClaudeUsageData(
            displayName: "User", email: "user@example.com", plan: "Pro",
            totalTokensIn: 14_500_000, totalTokensOut: 48_000,
            totalSessions: 38, totalProjects: 5, totalMessages: 420,
            tokensToday: 250_000, sessionsToday: 4,
            topProjectName: "MyProject", topProjectTokens: 8_000_000,
            rl5hUtil: -1, rl5hReset: 0, rl7dUtil: -1, rl7dReset: 0
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeUsageEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeUsageEntry>) -> Void) {
        let data = loadUsageData()
        let entry = ClaudeUsageEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadUsageData() -> ClaudeUsageData {
        let shared = UserDefaults(suiteName: "N6V3K529MB.claudeUsageTracker")
        guard let jsonString = shared?.string(forKey: "claudeWidgetData"),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ClaudeUsageData(
                displayName: "No data", email: "Launch the menu bar app", plan: "—",
                totalTokensIn: 0, totalTokensOut: 0, totalSessions: 0,
                totalProjects: 0, totalMessages: 0, tokensToday: 0,
                sessionsToday: 0, topProjectName: "—", topProjectTokens: 0,
                rl5hUtil: -1, rl5hReset: 0, rl7dUtil: -1, rl7dReset: 0
            )
        }

        return ClaudeUsageData(
            displayName: json["displayName"] as? String ?? "Unknown",
            email: json["email"] as? String ?? "Unknown",
            plan: json["plan"] as? String ?? "Unknown",
            totalTokensIn: json["totalTokensIn"] as? Int ?? 0,
            totalTokensOut: json["totalTokensOut"] as? Int ?? 0,
            totalSessions: json["totalSessions"] as? Int ?? 0,
            totalProjects: json["totalProjects"] as? Int ?? 0,
            totalMessages: json["totalMessages"] as? Int ?? 0,
            tokensToday: json["tokensToday"] as? Int ?? 0,
            sessionsToday: json["sessionsToday"] as? Int ?? 0,
            topProjectName: json["topProjectName"] as? String ?? "—",
            topProjectTokens: json["topProjectTokens"] as? Int ?? 0,
            rl5hUtil: json["rl5hUtil"] as? Double ?? -1,
            rl5hReset: json["rl5hReset"] as? Int ?? 0,
            rl7dUtil: json["rl7dUtil"] as? Double ?? -1,
            rl7dReset: json["rl7dReset"] as? Int ?? 0
        )
    }
}

// MARK: - Entry

struct ClaudeUsageEntry: TimelineEntry {
    let date: Date
    let data: ClaudeUsageData
}

// MARK: - Helpers

extension Int {
    var formatted: String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fK", Double(self) / 1_000) }
        return "\(self)"
    }
}

// MARK: - Colors

extension Color {
    static let wOrange = Color(red: 0.91, green: 0.47, blue: 0.18)
    static let wBg = Color(red: 0.05, green: 0.05, blue: 0.05)
    static let wSurface = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let wGreen = Color(red: 0.3, green: 0.8, blue: 0.4)
}

// MARK: - Widget View

struct ClaudeWidgetView: View {
    let entry: ClaudeUsageEntry
    var d: ClaudeUsageData { entry.data }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with app icon
            HStack(spacing: 8) {
                Image("WidgetIcon")
                    .resizable()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude Usage")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text(d.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Text(d.plan)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.wOrange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.wOrange.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Rate Limit Status
            rateLimitRow(label: "Session (5h)", util: d.rl5hUtil, resetAt: d.rl5hReset)
            rateLimitRow(label: "Weekly", util: d.rl7dUtil, resetAt: d.rl7dReset)

            // Today's Stats
            HStack(spacing: 6) {
                todayStat(label: "Today", value: d.tokensToday.formatted, sub: "tokens")
                todayStat(label: "Sessions", value: "\(d.sessionsToday)", sub: "today")
            }

            // All-time Stats Grid
            HStack(spacing: 6) {
                statCard(icon: "arrow.down", label: "Total In", value: d.totalTokensIn.formatted)
                statCard(icon: "arrow.up", label: "Total Out", value: d.totalTokensOut.formatted)
                statCard(icon: "bubble.left", label: "Messages", value: d.totalMessages.formatted)
                statCard(icon: "folder", label: "Projects", value: "\(d.totalProjects)")
            }

            // Most Active Project
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.wOrange)
                Text("Top project")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(d.topProjectName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(d.topProjectTokens.formatted)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.wOrange)
            }
            .padding(7)
            .background(Color.wSurface)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func rateLimitRow(label: String, util: Double, resetAt: Int) -> some View {
        HStack(spacing: 6) {
            if util >= 0 {
                // Critical — show percentage bar
                let pct = Int(util * 100)
                let barColor = pct >= 90 ? Color.red : Color.wOrange
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(pct)% used")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(barColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.wSurface)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor)
                                .frame(width: geo.size.width * CGFloat(util), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            } else {
                // Below threshold
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.wGreen)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("Below threshold")
                    .font(.system(size: 9))
                    .foregroundColor(.wGreen)
            }
        }
        .padding(7)
        .background(Color.wSurface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    func todayStat(label: String, value: String, sub: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.wOrange)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Text(sub)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.wSurface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    func statCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.wOrange)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 7))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color.wSurface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Widget Definition

struct ClaudeUsageWidget: Widget {
    let kind: String = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageProvider()) { entry in
            ClaudeWidgetView(entry: entry)
                .containerBackground(Color.wBg, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Track your Claude API usage at a glance.")
        .supportedFamilies([.systemLarge])
    }
}
