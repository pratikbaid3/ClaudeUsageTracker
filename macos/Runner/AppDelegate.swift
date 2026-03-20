import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var statusBar: NSStatusItem?

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
  }

  @objc func toggleWindow(_ sender: AnyObject) {
    guard let window = mainFlutterWindow else { return }

    if window.isVisible {
      window.orderOut(nil)
    } else {
      // Position below the status bar button
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
