import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var statusBar: NSStatusItem?
  var dataTimer: Timer?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Create the status bar item
    statusBar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusBar?.button {
      let icon = NSImage(named: "MenuBarIcon")
      icon?.size = NSSize(width: 22, height: 22)
      button.image = icon
      button.action = #selector(toggleWindow(_:))
    }

    // Style the main window as a popover-like panel
    if let window = mainFlutterWindow {
      window.styleMask = [.titled, .fullSizeContentView]
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.isMovable = false
      window.level = .floating
      window.setContentSize(NSSize(width: 350, height: 600))
      window.orderOut(nil) // Start hidden
    }

    // Write widget data on launch and periodically
    writeWidgetData()
    dataTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
      self?.writeWidgetData()
    }
  }

  func writeWidgetData() {
    DispatchQueue.global(qos: .background).async {
      let home = "/Users/pratikbaid"
      var widgetData: [String: Any] = [:]

      // Load account info
      let configPath = "\(home)/.claude.json"
      if let configData = FileManager.default.contents(atPath: configPath),
         let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
         let oauth = config["oauthAccount"] as? [String: Any] {
        widgetData["displayName"] = oauth["displayName"] as? String ?? "Unknown"
        widgetData["email"] = oauth["emailAddress"] as? String ?? "Unknown"
        let billingType = oauth["billingType"] as? String ?? "unknown"
        switch billingType {
        case "stripe_subscription": widgetData["plan"] = "Pro"
        case "enterprise": widgetData["plan"] = "Enterprise"
        case "free": widgetData["plan"] = "Free"
        default: widgetData["plan"] = billingType
        }
      }

      // Load project stats
      var totalTokensIn = 0
      var totalTokensOut = 0
      var totalSessions = 0
      var totalProjects = 0
      var totalMessages = 0
      var tokensToday = 0
      var sessionsToday = 0
      var projectTokens: [String: Int] = [:]

      let calendar = Calendar.current
      let startOfToday = calendar.startOfDay(for: Date())

      let projectsPath = "\(home)/.claude/projects/"
      if let projectDirs = try? FileManager.default.contentsOfDirectory(atPath: projectsPath) {
        for dir in projectDirs {
          let dirPath = "\(projectsPath)\(dir)"
          var isDir: ObjCBool = false
          guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }
          var hasSession = false
          let projectName = String(dir.replacingOccurrences(of: "-", with: "/").dropFirst())
          let shortName = projectName.components(separatedBy: "/").suffix(2).joined(separator: "/")
          var projTokens = 0

          if let files = try? FileManager.default.contentsOfDirectory(atPath: dirPath) {
            for file in files where file.hasSuffix(".jsonl") {
              hasSession = true
              totalSessions += 1
              var sessionHasToday = false
              let filePath = "\(dirPath)/\(file)"
              if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                for line in content.components(separatedBy: "\n") {
                  guard let lineData = line.data(using: .utf8),
                        let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                  let msgType = json["type"] as? String ?? ""
                  if msgType == "user" || msgType == "assistant" {
                    totalMessages += 1
                  }
                  if msgType == "assistant",
                     let message = json["message"] as? [String: Any],
                     let usage = message["usage"] as? [String: Any] {
                    let inp = (usage["input_tokens"] as? Int ?? 0) + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                    let out = usage["output_tokens"] as? Int ?? 0
                    let total = inp + out
                    totalTokensIn += inp
                    totalTokensOut += out
                    projTokens += total

                    // Check if this message is from today
                    if let ts = json["timestamp"] as? String,
                       let date = ISO8601DateFormatter().date(from: ts.replacingOccurrences(of: "\\.\\d+Z$", with: "Z", options: .regularExpression)),
                       date >= startOfToday {
                      tokensToday += total
                      sessionHasToday = true
                    }
                  }
                }
              }
              if sessionHasToday { sessionsToday += 1 }
            }
          }
          if hasSession {
            totalProjects += 1
            projectTokens[shortName] = projTokens
          }
        }
      }

      // Find most active project
      let topProject = projectTokens.max(by: { $0.value < $1.value })

      widgetData["totalTokensIn"] = totalTokensIn
      widgetData["totalTokensOut"] = totalTokensOut
      widgetData["totalSessions"] = totalSessions
      widgetData["totalProjects"] = totalProjects
      widgetData["totalMessages"] = totalMessages
      widgetData["tokensToday"] = tokensToday
      widgetData["sessionsToday"] = sessionsToday
      widgetData["topProjectName"] = topProject?.key ?? "—"
      widgetData["topProjectTokens"] = topProject?.value ?? 0

      // Get rate limit info from CLI
      let claudePath = "\(home)/.local/bin/claude"
      if FileManager.default.fileExists(atPath: claudePath) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)
        proc.arguments = ["-p", ".", "--output-format", "stream-json", "--verbose"]
        proc.environment = ProcessInfo.processInfo.environment
        proc.currentDirectoryURL = URL(fileURLWithPath: home)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        if let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
          for line in output.components(separatedBy: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "rate_limit_event",
                  let info = json["rate_limit_info"] as? [String: Any] else { continue }
            let type = info["rateLimitType"] as? String ?? ""
            let utilization = info["utilization"] as? Double
            let resetsAt = info["resetsAt"] as? Int ?? 0
            if type == "five_hour" {
              widgetData["rl5hUtil"] = utilization ?? -1
              widgetData["rl5hReset"] = resetsAt
            } else if type == "seven_day" {
              widgetData["rl7dUtil"] = utilization ?? -1
              widgetData["rl7dReset"] = resetsAt
            }
          }
        }
      }

      // Write to shared App Group UserDefaults
      if let jsonData = try? JSONSerialization.data(withJSONObject: widgetData),
         let jsonString = String(data: jsonData, encoding: .utf8) {
        let shared = UserDefaults(suiteName: "N6V3K529MB.claudeUsageTracker")
        shared?.set(jsonString, forKey: "claudeWidgetData")
        shared?.synchronize()
      }
    }
  }

  @objc func toggleWindow(_ sender: AnyObject) {
    guard let window = mainFlutterWindow else { return }

    if window.isVisible {
      window.orderOut(nil)
    } else {
      if let button = statusBar?.button,
         let buttonWindow = button.window {
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let windowWidth: CGFloat = 350
        let x = screenRect.midX - (windowWidth / 2)
        let y = screenRect.minY - window.frame.height

        window.setFrameOrigin(NSPoint(x: x, y: y))
      }

      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
