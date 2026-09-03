import AppKit

@MainActor
final class StatusController: NSObject, NSMenuDelegate {
  private var config: MotrixConfig
  private let engine: Aria2Engine
  private let client: Aria2RPCClient
  private let adaptiveSplitController: AdaptiveSplitController
  private let adaptiveConnectionController: AdaptiveConnectionController
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()

  private var timer: Timer?
  private let refreshCoalescer = RefreshCoalescer()
  private var isMenuOpen = false
  private var tasks: [Aria2Task] = []
  private var globalStat = Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 0, stopped: 0)
  private var lastError: String?
  private var progressSummary: ProgressSummary?
  private var hasEstablishedTaskBaseline = false
  private var knownCompletedTaskIDs = Set<String>()
  private var unreadCompletedTaskIDs = Set<String>()
  private var hasCreatedMainWindow = false
  private lazy var mainWindowController = MainWindowController(config: config, client: client)

  init(config: MotrixConfig, engine: Aria2Engine, client: Aria2RPCClient) {
    self.config = config
    self.engine = engine
    self.client = client
    self.adaptiveSplitController = AdaptiveSplitController(config: config, client: client)
    self.adaptiveConnectionController = AdaptiveConnectionController(config: config, client: client)
    super.init()
  }

  func start() {
    statusItem.button?.imagePosition = .imageLeading
    statusItem.button?.imageScaling = .scaleNone
    menu.delegate = self
    statusItem.menu = menu

    Task {
      await engine.ensureRunning(client: client)
      await refresh()
    }

    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.refresh(queueFollowUp: false)
      }
    }

    renderMenu()
  }

  func stop() async {
    timer?.invalidate()
    await engine.stopGracefully(client: client)
  }

  func showMainWindow() {
    markCompletedTasksRead()
    hasCreatedMainWindow = true
    mainWindowController.showWindow(nil)
  }

  func menuWillOpen(_ menu: NSMenu) {
    isMenuOpen = true
    markCompletedTasksRead()
    renderMenu()
  }

  func menuDidClose(_ menu: NSMenu) {
    isMenuOpen = false
  }

  private func refresh(queueFollowUp: Bool = true) async {
    await refreshCoalescer.run(queueFollowUp: queueFollowUp) { [self] in await refreshSnapshot() }
  }

  private func refreshSnapshot() async {
    do {
      let globalStat = try await client.getGlobalStat()
      let tasks = try await client.listTasks()
      CompletedControlFileCleaner.clean(tasks: tasks)
      let newlyCompletedIDs = updateCompletionState(with: tasks)
      if !newlyCompletedIDs.isEmpty, MotrixConfig.load().taskNotificationsEnabled {
        for task in tasks where newlyCompletedIDs.contains(task.id) {
          TaskNotificationManager.notifyDownloadCompleted(task)
        }
      }
      if hasCreatedMainWindow, mainWindowController.window?.isVisible == true {
        markCompletedTasksRead()
      }
      self.globalStat = globalStat.usingActiveTaskSpeeds(tasks)
      self.tasks = tasks
      self.progressSummary = makeProgressSummary(tasks)
      self.lastError = nil
      await adaptiveSplitController.observe(tasks)
      await adaptiveConnectionController.observe(tasks)
      renderMenu()
    } catch {
      self.lastError = String(describing: error)
      self.globalStat = Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 0, stopped: 0)
      self.progressSummary = nil
      await engine.ensureRunning(client: client)
      renderMenu()
    }
  }

  private func renderMenu() {
    renderStatusItem()
    guard isMenuOpen || menu.numberOfItems == 0 else { return }

    menu.removeAllItems()
    menu.addItem(headerItem())
    menu.addItem(NSMenuItem.separator())

    if let lastError {
      menu.addItem(menuItem(title: L10n.tr("status_menu.reconnect_engine"), systemImage: "arrow.clockwise", action: #selector(retry), keyEquivalent: "r"))
      let errorItem = NSMenuItem(title: lastError, action: nil, keyEquivalent: "")
      errorItem.isEnabled = false
      menu.addItem(errorItem)
    } else if tasks.isEmpty {
      let empty = menuItem(title: L10n.tr("status_menu.no_tasks"), systemImage: "tray", action: nil)
      empty.isEnabled = false
      menu.addItem(empty)
    } else {
      menu.addItem(sectionHeader(L10n.tr("status_menu.recent_tasks")))
      for task in tasks.prefix(6) {
        menu.addItem(taskMenuItem(task))
      }
    }

    menu.addItem(NSMenuItem.separator())
    menu.addItem(sectionHeader(L10n.tr("status_menu.quick_actions")))
    menu.addItem(menuItem(title: L10n.tr("status_menu.open_app"), systemImage: "macwindow", action: #selector(openMainWindow), keyEquivalent: "m"))
    menu.addItem(menuItem(title: L10n.tr("status_menu.new_download"), systemImage: "plus.circle", action: #selector(openAddTask), keyEquivalent: "n"))
    menu.addItem(menuItem(title: L10n.tr("status_menu.open_downloads"), systemImage: "folder", action: #selector(openDownloadDirectory), keyEquivalent: "o"))
    menu.addItem(menuItem(title: L10n.tr("status_menu.preferences"), systemImage: "gearshape", action: #selector(openPreferences), keyEquivalent: ","))
    menu.addItem(engineMenuItem())
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: L10n.tr("status_menu.quit"), action: #selector(quit), keyEquivalent: "q", target: self))
  }

  private func headerItem() -> NSMenuItem {
    let downloading = tasks.filter { $0.status == "active" && !$0.isSeeding }
    let seeding = tasks.filter(\.isSeeding)
    let state: String
    let detail: String
    let progress: Double?

    if lastError != nil {
      state = L10n.tr("status_menu.engine_disconnected")
      detail = L10n.tr("status_menu.engine_disconnected.detail")
      progress = nil
    } else if !downloading.isEmpty {
      state = L10n.format("status_menu.downloading_tasks", String(downloading.count))
      let percent = progressSummary?.percent ?? 0
      detail = L10n.format("status_menu.download_progress", Formatting.speed(globalStat.downloadSpeed), String(percent))
      progress = progressSummary?.progress
    } else if !seeding.isEmpty {
      state = L10n.format("status_menu.seeding_tasks", String(seeding.count))
      detail = L10n.format("status_menu.upload_speed", Formatting.speed(globalStat.uploadSpeed))
      progress = nil
    } else if globalStat.waiting > 0 {
      state = L10n.format("status_menu.waiting_tasks", String(globalStat.waiting))
      detail = L10n.tr("status_menu.waiting.detail")
      progress = nil
    } else {
      let completed = tasks.filter { $0.status == "complete" }.count
      state = engine.statusText == L10n.tr("engine.rpc_connected") ? L10n.tr("status_menu.engine_connected") : engine.statusText
      detail = completed > 0
        ? L10n.format("status_menu.recent_completed_tasks", String(completed))
        : L10n.tr("status_menu.no_active_tasks")
      progress = nil
    }

    let item = NSMenuItem()
    item.view = StatusMenuHeaderView(
      state: state,
      detail: detail,
      progress: progress,
      isError: lastError != nil
    )
    return item
  }

  private func sectionHeader(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.tertiaryLabelColor
      ]
    )
    item.isEnabled = false
    return item
  }

  private func menuItem(
    title: String,
    systemImage: String,
    action: Selector?,
    keyEquivalent: String = "",
    representedObject: Any? = nil
  ) -> NSMenuItem {
    let item = NSMenuItem(
      title: title,
      action: action,
      keyEquivalent: keyEquivalent,
      target: action == nil ? nil : self,
      representedObject: representedObject
    )
    if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
      image.isTemplate = true
      item.image = image
    }
    return item
  }

  private func taskImageName(_ task: Aria2Task) -> String {
    if task.isSeeding {
      return "arrow.up.circle.fill"
    } else {
      switch task.status {
      case "active": return "arrow.down.circle.fill"
      case "waiting": return "clock"
      case "paused": return "pause.circle.fill"
      case "complete": return "checkmark.circle.fill"
      case "error": return "exclamationmark.circle.fill"
      default: return "circle"
      }
    }
  }

  private func renderStatusItem() {
    if lastError != nil {
      statusItem.button?.image = StatusProgressIcon.renderError()
      statusItem.button?.title = ""
    } else if !unreadCompletedTaskIDs.isEmpty {
      statusItem.button?.image = StatusProgressIcon.renderCompletion()
      statusItem.button?.title = unreadCompletedTaskIDs.count > 1 ? "\(unreadCompletedTaskIDs.count)" : ""
    } else {
      let activeSummary = progressSummary?.hasIncompleteTasks == true ? progressSummary : nil
      statusItem.button?.image = StatusProgressIcon.render(activeSummary)
      statusItem.button?.title = activeSummary?.statusTitle ?? ""
    }
    statusItem.button?.toolTip = statusTooltip()
  }

  private func statusTooltip() -> String {
    if let lastError {
      return L10n.format("status_tooltip.rpc_disconnected", lastError)
    }

    if !unreadCompletedTaskIDs.isEmpty {
      return L10n.format("status_tooltip.completed_tasks", String(unreadCompletedTaskIDs.count))
    }

    if let progressSummary, progressSummary.hasIncompleteTasks {
      return L10n.format(
        "status_tooltip.task_progress",
        String(progressSummary.taskCount),
        String(progressSummary.percent)
      )
    }

    return AppIdentity.displayName
  }

  private func updateCompletionState(with tasks: [Aria2Task]) -> Set<String> {
    let completedIDs = Set(tasks.lazy.filter {
      $0.totalLength > 0 &&
        $0.completedLength >= $0.totalLength &&
        $0.status != "error" &&
        $0.status != "removed"
    }.map(\.id))
    guard hasEstablishedTaskBaseline else {
      knownCompletedTaskIDs = completedIDs
      hasEstablishedTaskBaseline = true
      return []
    }

    let newlyCompletedIDs = completedIDs.subtracting(knownCompletedTaskIDs)
    unreadCompletedTaskIDs.formUnion(newlyCompletedIDs)
    knownCompletedTaskIDs.formUnion(completedIDs)
    return newlyCompletedIDs
  }

  private func markCompletedTasksRead() {
    guard !unreadCompletedTaskIDs.isEmpty else {
      return
    }
    unreadCompletedTaskIDs.removeAll()
    renderStatusItem()
  }

  private func engineStatusItem() -> NSMenuItem {
    let error = engine.lastError.map { " (\($0))" } ?? ""
    let item = NSMenuItem(title: L10n.format("status_menu.engine_status", engine.statusText, error), action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private func engineMenuItem() -> NSMenuItem {
    let item = menuItem(title: L10n.tr("status_menu.engine_and_diagnostics"), systemImage: "bolt.horizontal.circle", action: nil)
    let submenu = NSMenu()
    submenu.addItem(engineStatusItem())
    let adaptiveSplitItem = NSMenuItem(
      title: L10n.format("status_menu.adaptive_split_status", adaptiveSplitController.statusText),
      action: nil,
      keyEquivalent: ""
    )
    adaptiveSplitItem.isEnabled = false
    submenu.addItem(adaptiveSplitItem)
    let adaptiveItem = NSMenuItem(
      title: L10n.format("status_menu.adaptive_status", adaptiveConnectionController.statusText),
      action: nil,
      keyEquivalent: ""
    )
    adaptiveItem.isEnabled = false
    submenu.addItem(adaptiveItem)
    submenu.addItem(NSMenuItem.separator())
    submenu.addItem(NSMenuItem(title: L10n.tr("status_menu.refresh_status"), action: #selector(refreshNow), keyEquivalent: "r", target: self))
    submenu.addItem(NSMenuItem(title: L10n.tr("status_menu.restart_engine"), action: #selector(restartEngine), keyEquivalent: "", target: self))
    submenu.addItem(NSMenuItem(title: L10n.tr("status_menu.engine_info"), action: #selector(showEngineInfo), keyEquivalent: "i", target: self))
    submenu.addItem(NSMenuItem.separator())
    submenu.addItem(NSMenuItem(title: L10n.tr("status_menu.open_config"), action: #selector(openConfigDirectory), keyEquivalent: "", target: self))
    submenu.addItem(NSMenuItem(title: L10n.tr("status_menu.open_log"), action: #selector(openAria2Log), keyEquivalent: "", target: self))
    item.submenu = submenu
    return item
  }

  private func makeProgressSummary(_ tasks: [Aria2Task]) -> ProgressSummary? {
    let incomplete = tasks.filter { task in
      task.status == "active" || task.status == "waiting" || task.status == "paused"
    }

    if incomplete.isEmpty {
      let hasCompleted = tasks.contains { $0.status == "complete" }
      return hasCompleted
        ? ProgressSummary(progress: 1, taskCount: 0, hasIncompleteTasks: false)
        : nil
    }

    let knownSizeTasks = incomplete.filter { $0.totalLength > 0 }
    guard !knownSizeTasks.isEmpty else {
      return ProgressSummary(progress: 0, taskCount: incomplete.count, hasIncompleteTasks: true)
    }

    let completed = knownSizeTasks.reduce(Int64(0)) { $0 + $1.completedLength }
    let total = knownSizeTasks.reduce(Int64(0)) { $0 + $1.totalLength }
    let progress = total > 0 ? Double(completed) / Double(total) : 0
    return ProgressSummary(progress: progress, taskCount: incomplete.count, hasIncompleteTasks: true)
  }

  private func taskMenuItem(_ task: Aria2Task) -> NSMenuItem {
    let item = menuItem(title: taskTitle(task), systemImage: taskImageName(task), action: nil)
    item.toolTip = task.name
    let submenu = NSMenu()

    submenu.addItem(NSMenuItem(title: L10n.tr("task.action.details"), action: #selector(openTaskDetails(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    submenu.addItem(NSMenuItem.separator())
    let detail = NSMenuItem(title: taskDetail(task), action: nil, keyEquivalent: "")
    detail.isEnabled = false
    submenu.addItem(detail)
    submenu.addItem(NSMenuItem.separator())

    if task.status == "active" {
      submenu.addItem(NSMenuItem(title: L10n.tr("action.pause"), action: #selector(pauseTask(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    } else if task.status == "paused" || task.status == "waiting" {
      submenu.addItem(NSMenuItem(title: L10n.tr("action.resume"), action: #selector(resumeTask(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    }

    if task.primaryFileURL != nil {
      submenu.addItem(NSMenuItem(title: L10n.tr("task.action.open_file"), action: #selector(openTaskFile(_:)), keyEquivalent: "", target: self, representedObject: task.id))
      submenu.addItem(NSMenuItem(title: L10n.tr("task.action.reveal_file"), action: #selector(revealTaskFile(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    }

    submenu.addItem(NSMenuItem(title: L10n.tr("action.remove"), action: #selector(removeTask(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    item.submenu = submenu
    return item
  }

  private func taskTitle(_ task: Aria2Task) -> String {
    let percent = Int(task.progress * 100)
    let suffix = "   \(percent)% · \(task.localizedStatus)"
    let availableNameWidth = max(80, 285 - menuTextWidth(suffix))
    return "\(truncatedMenuText(task.name, maximumWidth: availableNameWidth))\(suffix)"
  }

  private func truncatedMenuText(_ text: String, maximumWidth: CGFloat) -> String {
    guard menuTextWidth(text) > maximumWidth else {
      return text
    }

    let characters = Array(text)
    var lowerBound = 0
    var upperBound = max(0, characters.count - 1)
    var result = "…"

    while lowerBound <= upperBound {
      let retainedCount = (lowerBound + upperBound) / 2
      let prefixCount = (retainedCount + 1) / 2
      let suffixCount = retainedCount / 2
      let candidate = String(characters.prefix(prefixCount))
        + "…"
        + String(characters.suffix(suffixCount))

      if menuTextWidth(candidate) <= maximumWidth {
        result = candidate
        lowerBound = retainedCount + 1
      } else {
        upperBound = retainedCount - 1
      }
    }

    return result
  }

  private func menuTextWidth(_ text: String) -> CGFloat {
    (text as NSString).size(withAttributes: [
      .font: NSFont.menuFont(ofSize: NSFont.systemFontSize)
    ]).width
  }

  private func taskDetail(_ task: Aria2Task) -> String {
    let speed = task.downloadSpeed > 0 ? "  ·  \(Formatting.speed(task.downloadSpeed))" : ""
    return "\(Formatting.bytes(task.completedLength)) / \(Formatting.bytes(task.totalLength))\(speed)"
  }

  private func localizedStatus(_ status: String) -> String {
    switch status {
    case "active":
      return L10n.tr("task.status.downloading")
    case "waiting":
      return L10n.tr("task.status.waiting")
    case "paused":
      return L10n.tr("action.pause")
    case "complete":
      return L10n.tr("action.done")
    case "error":
      return L10n.tr("task.status.error")
    case "removed":
      return L10n.tr("task.status.removed")
    default:
      return status
    }
  }

  @objc private func retry() {
    Task {
      await engine.ensureRunning(client: client, force: true)
      await refresh()
    }
  }

  @objc private func restartEngine() {
    Task {
      let latestConfig = MotrixConfig.load()
      config = latestConfig
      client.updateConfig(latestConfig)
      engine.updateConfig(latestConfig)
      adaptiveSplitController.updateConfig(latestConfig)
      adaptiveConnectionController.updateConfig(latestConfig)
      await engine.restart(client: client)
      await refresh()
    }
  }

  @objc private func refreshNow() {
    Task { await refresh() }
  }

  @objc private func openMainWindow() {
    showMainWindow()
  }

  @objc private func openPreferences() {
    showMainWindow()
    mainWindowController.showPreferences()
  }

  @objc private func openTaskDetails(_ sender: NSMenuItem) {
    guard
      let gid = sender.representedObject as? String,
      let task = tasks.first(where: { $0.id == gid })
    else {
      return
    }

    showMainWindow()
    mainWindowController.showDetails(task)
  }

  @objc private func openAddTask() {
    showMainWindow()
    mainWindowController.showAddTask()
  }

  @objc private func pauseTask(_ sender: NSMenuItem) {
    guard let gid = sender.representedObject as? String else {
      return
    }

    Task {
      do {
        try await client.pause(gid)
        await refresh()
      } catch {
        showError(error)
      }
    }
  }

  @objc private func resumeTask(_ sender: NSMenuItem) {
    guard let gid = sender.representedObject as? String else {
      return
    }

    Task {
      do {
        try await client.unpause(gid)
        await refresh()
      } catch {
        showError(error)
      }
    }
  }

  @objc private func removeTask(_ sender: NSMenuItem) {
    guard let gid = sender.representedObject as? String else {
      return
    }

    guard
      let task = tasks.first(where: { $0.id == gid }),
      MotrixConfig.load().skipsRemovalConfirmation || TaskRemovalConfirmation.confirm(task)
    else {
      return
    }

    Task {
      do {
        if task.status == "complete" || task.status == "error" || task.status == "removed" {
          try await client.removeDownloadResult(gid)
        } else {
          try await client.remove(gid)
        }
        await refresh()
      } catch {
        showError(error)
      }
    }
  }

  @objc private func openTaskFile(_ sender: NSMenuItem) {
    guard
      let gid = sender.representedObject as? String,
      let url = tasks.first(where: { $0.id == gid })?.primaryFileURL
    else {
      return
    }

    NSWorkspace.shared.open(url)
  }

  @objc private func revealTaskFile(_ sender: NSMenuItem) {
    guard
      let gid = sender.representedObject as? String,
      let url = tasks.first(where: { $0.id == gid })?.primaryFileURL
    else {
      return
    }

    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @objc private func openDownloadDirectory() {
    NSWorkspace.shared.open(config.downloadDirectory)
  }

  @objc private func openConfigDirectory() {
    NSWorkspace.shared.open(config.supportDirectory)
  }

  @objc private func openAria2Log() {
    NSWorkspace.shared.open(config.aria2LogPath)
  }

  @objc private func showEngineInfo() {
    let alert = NSAlert()
    alert.messageText = L10n.tr("engine_info.title")
    var details = [
      "RPC: 127.0.0.1:\(config.rpcPort)",
      L10n.format("engine_info.download_directory", config.downloadDirectory.path),
      "session: \(config.sessionPath.path)",
      "aria2c: \(config.aria2BinaryPath?.path ?? L10n.tr("common.not_found"))",
      L10n.format("engine_info.status", engine.statusText),
      L10n.format("engine_info.argument_count", String(config.aria2StartArguments().count)),
      "max-connection-per-server: \(config.systemConfig["max-connection-per-server"] ?? "-")",
      "split: \(config.systemConfig["split"] ?? "-")",
      "max-overall-download-limit: \(config.systemConfig["max-overall-download-limit"] ?? "-")"
    ]
    if let build = Aria2BuildInfo.load() {
      details.insert(contentsOf: [
        L10n.format("engine_info.build", build.aria2Version, build.shortCommit),
        L10n.format("engine_info.platform", build.architecture, build.minimumMacOS, build.tlsBackend),
        L10n.format("engine_info.compatibility", String(build.compatibility.maxConnectionsPerServer)),
        L10n.format("engine_info.dependencies", build.dependencySummary)
      ], at: 0)
    }
    alert.informativeText = details.joined(separator: "\n")
    alert.addButton(withTitle: L10n.tr("action.ok"))
    alert.runModal()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func showError(_ error: Error) {
    let alert = NSAlert(error: error)
    alert.runModal()
  }
}

private extension NSMenuItem {
  convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject?, representedObject: Any? = nil) {
    self.init(title: title, action: action, keyEquivalent: keyEquivalent)
    self.target = target
    self.representedObject = representedObject
  }
}
