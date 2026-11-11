import AppKit

@MainActor
final class StatusController: NSObject, NSMenuDelegate {
  private var config: AppConfig
  private let engine: Aria2Engine
  private let client: Aria2RPCClient
  private let adaptiveSplitController: AdaptiveSplitController
  private let adaptiveConnectionController: AdaptiveConnectionController
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()

  private var timer: Timer?
  private var downloadActivity: NSObjectProtocol?
  private var activityPreventsSleep = false
  private let events = Aria2EventStream()
  private let refreshCoalescer = RefreshCoalescer()
  private var isMenuOpen = false
  private var tasks: [Aria2Task] = []
  private var globalStat = Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 0, stopped: 0)
  private var lastError: String?
  private var progressSummary: ProgressSummary?
  private var renderedStatusKey: String?
  private var hasEstablishedTaskBaseline = false
  private var knownCompletedTaskIDs = Set<String>()
  private var unreadCompletedTaskIDs = Set<String>()
  private let snapshots: TaskSnapshotStore
  private var isRestartingEngine = false
  private var isStopping = false
  private var hasCreatedMainWindow = false
  private lazy var mainWindowController = MainWindowController(
    config: config,
    client: client,
    snapshots: snapshots,
    restartEngine: { [weak self] in
      guard let self else { return false }
      return await self.restartEngineAndReport()
    },
    settingsDidSave: { [weak self] config in
      self?.applySettings(config)
    }
  )

  init(config: AppConfig, engine: Aria2Engine, client: Aria2RPCClient) {
    self.config = config
    self.engine = engine
    self.client = client
    self.adaptiveSplitController = AdaptiveSplitController(config: config, client: client)
    self.adaptiveConnectionController = AdaptiveConnectionController(config: config, client: client)
    self.snapshots = TaskSnapshotStore(config: config, client: client)
    super.init()
    snapshots.observe { [weak self] in self?.receiveSnapshot() }
    events.onEvent = { [weak self] in
      Task { await self?.refresh() }
    }
  }

  func start() {
    statusItem.button?.imagePosition = .imageLeading
    statusItem.button?.imageScaling = .scaleNone
    menu.delegate = self
    statusItem.menu = menu

    Task {
      await engine.ensureRunning(client: client)
      await refresh()
      scheduleRefresh()
    }

    renderMenu()
  }

  func stop() async {
    isStopping = true
    timer?.invalidate()
    events.disconnect()
    updateDownloadActivity()
    await snapshots.refresh()
    snapshots.isSuspended = true
    snapshots.invalidate()
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
    renderStatusItem()
    rebuildMenu()
  }

  func menuDidClose(_ menu: NSMenu) {
    isMenuOpen = false
  }

  private func refresh(queueFollowUp: Bool = true) async {
    await refreshCoalescer.run(queueFollowUp: queueFollowUp) { [self] in
      guard !isRestartingEngine, !isStopping else { return }
      await snapshots.refresh(queueFollowUp: queueFollowUp)
      if !snapshots.isConnected, !isStopping { await engine.ensureRunning(client: client) }
    }
  }

  private func scheduleRefresh() {
    timer?.invalidate()
    guard !isStopping, !isRestartingEngine else { return }
    let timer = Timer(timeInterval: snapshots.pollingInterval, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        await self.refresh(queueFollowUp: false)
        self.scheduleRefresh()
      }
    }
    // The default mode pauses while a menu or a modal alert is tracking events,
    // which froze the status item for as long as the menu stayed open.
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  /// A menu bar app without a window is put into App Nap, which delays timers
  /// by several seconds. Hold an activity while downloads are in the queue,
  /// and let it keep the Mac awake while one is transferring if the user
  /// asked for that. Seeding alone never keeps the Mac awake.
  private func updateDownloadActivity() {
    let isQueued = snapshots.isConnected && !isStopping
      && tasks.contains { $0.status == "active" || $0.status == "waiting" }
    let preventsSleep = isQueued && config.preventsSleepWhileDownloading
      && tasks.contains { $0.status == "active" && !$0.isSeeding }

    if let activity = downloadActivity, !isQueued || preventsSleep != activityPreventsSleep {
      ProcessInfo.processInfo.endActivity(activity)
      downloadActivity = nil
    }
    if isQueued, downloadActivity == nil {
      downloadActivity = ProcessInfo.processInfo.beginActivity(
        options: preventsSleep ? .userInitiated : .userInitiatedAllowingIdleSystemSleep,
        reason: "Downloading"
      )
      activityPreventsSleep = preventsSleep
    }
  }

  private func receiveSnapshot() {
    let tasks = snapshots.liveTasks
    if snapshots.isConnected {
      let newlyCompletedIDs = updateCompletionState(with: tasks)
      if !newlyCompletedIDs.isEmpty, config.taskNotificationsEnabled {
        for task in tasks where newlyCompletedIDs.contains(task.id) {
          TaskNotificationManager.notifyDownloadCompleted(task)
        }
      }
      if hasCreatedMainWindow, mainWindowController.window?.isVisible == true {
        markCompletedTasksRead()
      }
      globalStat = snapshots.stat
      self.tasks = tasks
      progressSummary = makeProgressSummary(tasks)
      events.connect(port: client.runningConfig.rpcPort)
      Task {
        await adaptiveSplitController.observe(tasks)
        await adaptiveConnectionController.observe(tasks)
      }
    } else {
      progressSummary = nil
    }
    updateDownloadActivity()
    lastError = snapshots.errorText
    renderMenu()
    scheduleRefresh()
  }

  private func renderMenu() {
    renderStatusItem()
    if menu.numberOfItems == 0 {
      rebuildMenu()
    } else if isMenuOpen {
      refreshOpenMenu()
    }
  }

  /// Rebuilding an open menu drops the highlight and closes its submenus, so
  /// only the header and the listed task rows are updated in place.
  private func refreshOpenMenu() {
    if let header = menu.items.first, header.view is StatusMenuHeaderView {
      header.view = headerView()
    }
    for item in menu.items {
      guard
        let gid = item.identifier?.rawValue,
        let task = tasks.first(where: { $0.id == gid })
      else {
        continue
      }
      let title = taskTitle(task)
      if item.title != title { item.title = title }
      item.image = menuImage(taskImageName(task), description: title)
    }
  }

  private func rebuildMenu() {
    menu.removeAllItems()
    let header = NSMenuItem()
    header.view = headerView()
    menu.addItem(header)
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

  private func headerView() -> StatusMenuHeaderView {
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

    return StatusMenuHeaderView(
      state: state,
      detail: detail,
      progress: progress,
      isError: lastError != nil
    )
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
    item.image = menuImage(systemImage, description: title)
    return item
  }

  private func menuImage(_ systemImage: String, description: String) -> NSImage? {
    let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: description)
    image?.isTemplate = true
    return image
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
    // A poll that changes nothing visible should not redraw the status item.
    let activeSummary = progressSummary?.hasIncompleteTasks == true ? progressSummary : nil
    let showsCompletion = showsCompletionBadge
    let key = [
      lastError ?? "",
      showsCompletion ? String(unreadCompletedTaskIDs.count) : "",
      activeSummary.map { "\($0.taskCount):\($0.percent)" } ?? ""
    ].joined(separator: "|")
    guard key != renderedStatusKey else { return }
    renderedStatusKey = key

    if lastError != nil {
      statusItem.button?.image = StatusProgressIcon.renderError()
      statusItem.button?.title = ""
    } else if showsCompletion {
      statusItem.button?.image = StatusProgressIcon.renderCompletion()
      statusItem.button?.title = unreadCompletedTaskIDs.count > 1 ? "\(unreadCompletedTaskIDs.count)" : ""
    } else {
      statusItem.button?.image = StatusProgressIcon.render(activeSummary)
      statusItem.button?.title = activeSummary?.statusTitle ?? ""
    }
    statusItem.button?.toolTip = statusTooltip()
  }

  /// The completion badge used to replace the progress ring until the menu was
  /// opened, hiding the progress of every download that was still running.
  private var showsCompletionBadge: Bool {
    !unreadCompletedTaskIDs.isEmpty && !tasks.contains { $0.status == "active" && !$0.isSeeding }
  }

  private func statusTooltip() -> String {
    if let lastError {
      return L10n.format("status_tooltip.rpc_disconnected", lastError)
    }

    if showsCompletionBadge {
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
    // A seeding torrent is "active" but finished; counting it pinned the ring
    // near 100%.
    let unfinished = tasks.filter { task in
      (task.status == "active" || task.status == "waiting" || task.status == "paused") && !task.isSeeding
    }
    // Paused tasks do not move. While anything is queued to run, measure only
    // that queue so a large paused task cannot flatten the percentage.
    let queued = unfinished.filter { $0.status != "paused" }
    let incomplete = queued.isEmpty ? unfinished : queued

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
    item.identifier = NSUserInterfaceItemIdentifier(task.id)
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

  @objc private func retry() {
    Task {
      await engine.ensureRunning(client: client, force: true)
      await refresh()
    }
  }

  @objc private func restartEngine() {
    Task { _ = await restartEngineAndReport() }
  }

  private func restartEngineAndReport() async -> Bool {
    guard !isRestartingEngine else { return false }
    isRestartingEngine = true
    events.disconnect()
    snapshots.isSuspended = true
    snapshots.invalidate()
    defer {
      isRestartingEngine = false
      snapshots.isSuspended = false
      scheduleRefresh()
    }
    let latestConfig = config
    let succeeded = await engine.restart(client: client, config: latestConfig)
    client.updateDefaults(config)
    if succeeded, hasCreatedMainWindow {
      mainWindowController.engineDidRestart(latestConfig)
    }
    snapshots.isSuspended = false
    await snapshots.refresh()
    return succeeded
  }

  private func applySettings(_ config: AppConfig) {
    self.config = config
    // The status item text is localized, so a language change must redraw it.
    renderedStatusKey = nil
    renderMenu()
    updateDownloadActivity()
    client.updateDefaults(config)
    adaptiveSplitController.updateConfig(config)
    adaptiveConnectionController.updateConfig(config)
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
      config.skipsRemovalConfirmation || TaskRemovalConfirmation.confirm(task)
    else {
      return
    }

    Task {
      do {
        if task.status == "complete" || task.status == "error" || task.status == "removed" {
          try await client.removeDownloadResult(gid)
        } else {
          try await client.remove(gid)
          // aria2 keeps no result to remove until the task has stopped.
          try? await Task.sleep(for: .milliseconds(80))
          try? await client.removeDownloadResult(gid)
        }
        snapshots.remove([gid])
        await snapshots.refresh()
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
