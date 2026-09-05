import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
  private let model: MainWindowModel
  private let initialContentSize: NSSize
  private var hasAppliedInitialSize = false

  init(
    config: MotrixConfig,
    client: Aria2RPCClient,
    restartEngine: @escaping () async -> Bool = { false },
    settingsDidSave: @escaping (MotrixConfig) -> Void = { _ in }
  ) {
    self.model = MainWindowModel(
      config: config,
      client: client,
      restartEngine: restartEngine,
      settingsDidSave: settingsDidSave
    )

    let baseSize = NSSize(width: 1080, height: 720)
    let widthReduction = 0.85 * 0.90
    let heightReduction = 0.85
    let desiredSize = NSSize(
      width: baseSize.width * 1.5 * widthReduction,
      height: baseSize.height * 1.5 * heightReduction
    )
    let visibleSize = NSScreen.main?.visibleFrame.size ?? desiredSize
    let initialSize = NSSize(
      width: min(desiredSize.width, visibleSize.width * 0.96 * widthReduction),
      height: min(desiredSize.height, visibleSize.height * 0.94 * heightReduction)
    )
    self.initialContentSize = initialSize

    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: initialSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = AppIdentity.displayName
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.minSize = NSSize(width: 920, height: 560)
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(rootView: MainWindowView(model: model))

    super.init(window: window)
    window.delegate = self
    window.center()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func showWindow(_ sender: Any?) {
    NSApp.setActivationPolicy(.regular)
    super.showWindow(sender)
    if !hasAppliedInitialSize {
      window?.setContentSize(initialContentSize)
      window?.center()
      hasAppliedInitialSize = true
    }
    NSApp.activate(ignoringOtherApps: true)
    model.startRefreshing()
  }

  func showDetails(_ task: Aria2Task) {
    model.showDetails(task)
  }

  func showPreferences() {
    model.select(.preferences(.general))
  }

  func showAddTask() {
    model.closeDetails()
    model.showingAddTask = true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    model.stopRefreshing()
    NSApp.setActivationPolicy(.accessory)
    return false
  }
}
