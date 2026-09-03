import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  private var controller: StatusController?
  private var terminationInProgress = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    let config = MotrixConfig.load()
    L10n.configure(language: config.appLanguage)
    installApplicationMenu()
    try? LoginItemManager.apply(config.openAtLoginEnabled)
    if config.taskNotificationsEnabled {
      TaskNotificationManager.requestAuthorization()
    }
    UNUserNotificationCenter.current().delegate = self

    let engine = Aria2Engine(config: config)
    let client = Aria2RPCClient(config: config)
    controller = StatusController(config: config, engine: engine, client: client)
    controller?.start()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationInProgress, let controller else {
      return .terminateNow
    }

    terminationInProgress = true
    Task {
      await controller.stop()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    controller?.showMainWindow()
    return true
  }

  @MainActor
  private func installApplicationMenu() {
    let mainMenu = NSMenu()
    let applicationMenuItem = NSMenuItem(title: AppIdentity.displayName, action: nil, keyEquivalent: "")
    let applicationMenu = NSMenu(title: AppIdentity.displayName)
    let quitItem = NSMenuItem(
      title: L10n.tr("status_menu.quit"),
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.keyEquivalentModifierMask = [.command]
    quitItem.target = NSApp
    applicationMenu.addItem(quitItem)
    applicationMenuItem.submenu = applicationMenu
    mainMenu.addItem(applicationMenuItem)

    let editMenuItem = NSMenuItem(title: L10n.tr("menu.edit"), action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: L10n.tr("menu.edit"))
    editMenu.addItem(commandItem(L10n.tr("action.undo"), action: Selector(("undo:")), keyEquivalent: "z"))
    editMenu.addItem(commandItem(
      L10n.tr("action.redo"),
      action: Selector(("redo:")),
      keyEquivalent: "z",
      modifiers: [.command, .shift]
    ))
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(commandItem(L10n.tr("action.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(commandItem(L10n.tr("action.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(commandItem(L10n.tr("action.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(commandItem(L10n.tr("action.select_all"), action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a"))
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    NSApp.mainMenu = mainMenu
  }

  @MainActor
  private func commandItem(
    _ title: String,
    action: Selector,
    keyEquivalent: String,
    modifiers: NSEvent.ModifierFlags = [.command]
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.keyEquivalentModifierMask = modifiers
    return item
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
