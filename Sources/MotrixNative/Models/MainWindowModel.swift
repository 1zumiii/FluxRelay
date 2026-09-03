import AppKit
import SwiftUI

struct NewDownloadOptions {
  var directory: URL
  var outputName = ""
  var headers = ""
  var cookie = ""
  var referer = ""
  var checksum = ""
  var pauseAtStart = false

  var aria2Options: [String: Any] {
    var result: [String: Any] = [:]
    let outputName = outputName.trimmingCharacters(in: .whitespacesAndNewlines)
    let referer = referer.trimmingCharacters(in: .whitespacesAndNewlines)
    let checksum = checksum.trimmingCharacters(in: .whitespacesAndNewlines)
    var headerLines = headers
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let cookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)

    if !outputName.isEmpty { result["out"] = outputName }
    if !referer.isEmpty { result["referer"] = referer }
    if !checksum.isEmpty { result["checksum"] = checksum }
    if !cookie.isEmpty { headerLines.append("Cookie: \(cookie)") }
    if !headerLines.isEmpty { result["header"] = headerLines }
    if pauseAtStart { result["pause"] = "true" }
    return result
  }
}

struct PreparedTorrent: Identifiable {
  let id: String
  let sourceURL: URL
  let directory: URL
  let files: [Aria2TaskFile]
}

private enum NewTaskError: LocalizedError {
  case noTorrentFiles
  case noFilesSelected

  var errorDescription: String? {
    switch self {
    case .noTorrentFiles: return L10n.tr("torrent.error.no_files")
    case .noFilesSelected: return L10n.tr("torrent.error.no_selection")
    }
  }
}

@MainActor
final class MainWindowModel: ObservableObject {
  enum TaskSort: String, CaseIterable, Identifiable {
    case engine
    case name
    case progress
    case speed
    case size

    var id: String { rawValue }

    var title: String {
      switch self {
      case .engine: return L10n.tr("task.sort.engine")
      case .name: return L10n.tr("task.sort.name")
      case .progress: return L10n.tr("task.sort.progress")
      case .speed: return L10n.tr("task.sort.speed")
      case .size: return L10n.tr("task.sort.size")
      }
    }
  }

  enum QueueMove {
    case top
    case up
    case down
    case bottom

    var position: Int {
      switch self {
      case .top, .bottom: return 0
      case .up: return -1
      case .down: return 1
      }
    }

    var how: String {
      switch self {
      case .top: return "POS_SET"
      case .up, .down: return "POS_CUR"
      case .bottom: return "POS_END"
      }
    }
  }

  enum Filter: Int, CaseIterable, Identifiable {
    case all
    case active
    case waiting
    case paused
    case completed

    var id: Int { rawValue }

    var title: String {
      switch self {
      case .all: return L10n.tr("task.filter.all")
      case .active: return L10n.tr("task.status.downloading")
      case .waiting: return L10n.tr("task.filter.waiting")
      case .paused: return L10n.tr("task.status.paused")
      case .completed: return L10n.tr("task.status.completed")
      }
    }

    var systemImage: String {
      switch self {
      case .all: return "tray.full"
      case .active: return "arrow.down.circle.fill"
      case .waiting: return "clock.fill"
      case .paused: return "pause.circle.fill"
      case .completed: return "checkmark.circle.fill"
      }
    }

    var color: Color {
      switch self {
      case .all: return .indigo
      case .active: return .teal
      case .waiting: return .orange
      case .paused: return .gray
      case .completed: return .green
      }
    }
  }

  enum Section: Hashable {
    case tasks(Filter)
    case preferences(PreferencesSection)
  }

  enum PreferencesSection: Int, CaseIterable, Identifiable {
    case general
    case download
    case bittorrent
    case connection

    var id: Int { rawValue }

    var title: String {
      switch self {
      case .general: return L10n.tr("preferences.section.general")
      case .download: return L10n.tr("preferences.section.download")
      case .bittorrent: return "BitTorrent"
      case .connection: return L10n.tr("preferences.section.connection")
      }
    }

    var subtitle: String {
      switch self {
      case .general: return L10n.tr("preferences.section.general.subtitle")
      case .download: return L10n.tr("preferences.section.download.subtitle")
      case .bittorrent: return L10n.tr("preferences.section.bittorrent.subtitle")
      case .connection: return L10n.tr("preferences.section.connection.subtitle")
      }
    }

    var systemImage: String {
      switch self {
      case .general: return "gearshape.fill"
      case .download: return "arrow.down.circle.fill"
      case .bittorrent: return "point.3.connected.trianglepath.dotted"
      case .connection: return "network"
      }
    }

    var color: Color {
      switch self {
      case .general: return .blue
      case .download: return .teal
      case .bittorrent: return .purple
      case .connection: return .orange
      }
    }
  }

  @Published private(set) var config: MotrixConfig
  let client: Aria2RPCClient

  @Published var tasks: [Aria2Task] = []
  @Published var globalStat = Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 0, stopped: 0)
  @Published var filter: Filter = .all
  @Published var selectedSection: Section = .tasks(.all)
  @Published var searchText = ""
  @Published var taskSort: TaskSort = .engine
  @Published var isSelectingTasks = false
  @Published var selectedTaskIDs = Set<String>()
  @Published var errorText: String?
  @Published var showingAddTask = false
  @Published var selectedTaskID: String?
  @Published private(set) var selectedPeers: [Aria2Peer] = []
  @Published private(set) var selectedTaskOptions: [String: String] = [:]
  @Published var settings = SettingsDraft()
  @Published var settingsSaved = false
  @Published private(set) var isTestingProxy = false
  @Published private(set) var proxyTestMessage: String?

  private var refreshTimer: Timer?
  private let refreshCoalescer = RefreshCoalescer()

  init(config: MotrixConfig, client: Aria2RPCClient) {
    self.config = config
    self.client = client
    self.settings = SettingsDraft(config: config)
  }

  var filteredTasks: [Aria2Task] {
    guard case .tasks(let filter) = selectedSection else {
      return []
    }

    var result = tasks

    switch filter {
    case .all:
      break
    case .active:
      result = result.filter { $0.status == "active" }
    case .waiting:
      result = result.filter { $0.status == "waiting" }
    case .paused:
      result = result.filter { $0.status == "paused" }
    case .completed:
      result = result.filter { $0.status == "complete" }
    }

    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
      result = result.filter {
        $0.name.localizedCaseInsensitiveContains(query) ||
          ($0.primaryFileURL?.path.localizedCaseInsensitiveContains(query) ?? false)
      }
    }

    switch taskSort {
    case .engine:
      break
    case .name:
      result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    case .progress:
      result.sort { $0.progress > $1.progress }
    case .speed:
      result.sort { $0.downloadSpeed > $1.downloadSpeed }
    case .size:
      result.sort { $0.totalLength > $1.totalLength }
    }

    return result
  }

  var summaryText: String {
    L10n.format(
      "task.summary",
      String(filteredTasks.count),
      Formatting.speed(globalStat.downloadSpeed),
      Formatting.speed(globalStat.uploadSpeed)
    )
  }

  var selectedTask: Aria2Task? {
    guard let selectedTaskID else { return nil }
    return tasks.first { $0.id == selectedTaskID }
  }

  var selectedTasks: [Aria2Task] {
    tasks.filter { selectedTaskIDs.contains($0.id) }
  }

  var defaultDownloadDirectory: URL { config.downloadDirectory }
  var defaultPauseAtStart: Bool { settings.pause }

  func count(for filter: Filter) -> Int {
    switch filter {
    case .all:
      return tasks.count
    case .active:
      return tasks.filter { $0.status == "active" }.count
    case .waiting:
      return tasks.filter { $0.status == "waiting" }.count
    case .paused:
      return tasks.filter { $0.status == "paused" }.count
    case .completed:
      return tasks.filter { $0.status == "complete" }.count
    }
  }

  func select(_ section: Section) {
    selectedTaskID = nil
    selectedTaskOptions = [:]
    selectedPeers = []
    endTaskSelection()
    selectedSection = section
    if case .tasks(let filter) = section {
      self.filter = filter
    }
  }

  func showDetails(_ task: Aria2Task) {
    selectedTaskID = task.id
    selectedTaskOptions = [:]
    selectedPeers = []
    Task { await refreshDetails(for: task) }
  }

  func setTaskSelection(_ enabled: Bool) {
    isSelectingTasks = enabled
    if !enabled { selectedTaskIDs.removeAll() }
  }

  func toggleTaskSelection(_ task: Aria2Task) {
    if selectedTaskIDs.contains(task.id) {
      selectedTaskIDs.remove(task.id)
    } else {
      selectedTaskIDs.insert(task.id)
    }
  }

  func selectAllVisibleTasks() {
    selectedTaskIDs = Set(filteredTasks.map(\.id))
  }

  func endTaskSelection() {
    isSelectingTasks = false
    selectedTaskIDs.removeAll()
  }

  func closeDetails() {
    selectedTaskID = nil
    selectedTaskOptions = [:]
    selectedPeers = []
  }

  func copyGID(_ task: Aria2Task) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(task.id, forType: .string)
  }

  func startRefreshing() {
    refreshTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.refresh(queueFollowUp: false)
      }
    }
    Task { await refresh() }
  }

  func stopRefreshing() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  func refresh(queueFollowUp: Bool = true) async {
    await refreshCoalescer.run(queueFollowUp: queueFollowUp) { [self] in await refreshSnapshot() }
  }

  private func refreshSnapshot() async {
    do {
      let latestStat = try await client.getGlobalStat()
      let latestTasks = try await client.listTasks()
      tasks = latestTasks
      let retainedIDs = selectedTaskIDs.intersection(Set(latestTasks.map(\.id)))
      if selectedTaskIDs != retainedIDs { selectedTaskIDs = retainedIDs }
      let displayedStat = latestStat.usingActiveTaskSpeeds(latestTasks)
      if globalStat != displayedStat { globalStat = displayedStat }
      if let selectedTaskID, let selected = latestTasks.first(where: { $0.id == selectedTaskID }) {
        await refreshDetails(for: selected)
      } else {
        if !selectedTaskOptions.isEmpty { selectedTaskOptions = [:] }
        if !selectedPeers.isEmpty { selectedPeers = [] }
      }
      if errorText != nil { errorText = nil }
    } catch {
      let message = L10n.tr("engine.rpc_disconnected")
      if errorText != message { errorText = message }
    }
  }

  @discardableResult
  func addLink(_ uri: String, options: NewDownloadOptions? = nil) async -> Bool {
    let uri = uri.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !uri.isEmpty else {
      return false
    }

    let options = options ?? NewDownloadOptions(directory: config.downloadDirectory)
    do {
      try await client.addURI(
        uri,
        directory: options.directory,
        additionalOptions: options.aria2Options
      )
      await refresh()
      return true
    } catch {
      NSAlert(error: error).runModal()
      return false
    }
  }

  func prepareTorrent(_ fileURL: URL, directory: URL) async -> PreparedTorrent? {
    var gid: String?
    do {
      gid = try await client.addTorrent(
        fileURL,
        directory: directory,
        additionalOptions: ["pause": "true"]
      )

      var files: [Aria2TaskFile] = []
      for _ in 0..<10 where files.isEmpty {
        files = try await client.getFiles(gid ?? "")
        if files.isEmpty {
          try? await Task.sleep(for: .milliseconds(100))
        }
      }

      guard let gid, !files.isEmpty else {
        throw NewTaskError.noTorrentFiles
      }
      await refresh()
      return PreparedTorrent(id: gid, sourceURL: fileURL, directory: directory, files: files)
    } catch {
      if let gid {
        try? await client.remove(gid)
      }
      NSAlert(error: error).runModal()
      await refresh()
      return nil
    }
  }

  @discardableResult
  func startPreparedTorrent(
    _ torrent: PreparedTorrent,
    selectedFileIDs: Set<String>,
    pauseAtStart: Bool
  ) async -> Bool {
    guard !selectedFileIDs.isEmpty else {
      NSAlert(error: NewTaskError.noFilesSelected).runModal()
      return false
    }

    do {
      let selected = selectedFileIDs
        .compactMap(Int.init)
        .sorted()
        .map(String.init)
        .joined(separator: ",")
      try await client.changeOption(torrent.id, options: ["select-file": selected])
      if !pauseAtStart {
        try await client.unpause(torrent.id)
      }
      await refresh()
      return true
    } catch {
      NSAlert(error: error).runModal()
      return false
    }
  }

  func discardPreparedTorrent(_ torrent: PreparedTorrent) async {
    try? await client.remove(torrent.id)
    await refresh()
  }

  private func refreshDetails(for task: Aria2Task) async {
    let options = (try? await client.getOption(task.id)) ?? [:]
    let peers = task.isBitTorrent ? ((try? await client.getPeers(task.id)) ?? []) : []
    guard selectedTaskID == task.id else { return }
    if selectedTaskOptions != options { selectedTaskOptions = options }
    if selectedPeers != peers { selectedPeers = peers }
  }

  func pause(_ task: Aria2Task) async {
    do {
      try await client.pause(task.id)
      tasks = tasks.map {
        $0.id == task.id
          ? $0.updating(status: "paused", downloadSpeed: 0, uploadSpeed: 0)
          : $0
      }
      globalStat = globalStat.usingActiveTaskSpeeds(tasks)
      await refresh()
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  func resume(_ task: Aria2Task) async {
    await perform {
      try await client.unpause(task.id)
    }
  }

  func pauseSelectedTasks() async {
    await performBatch(selectedTasks.filter { $0.status == "active" }) { task in
      try await client.pause(task.id)
    }
  }

  func resumeSelectedTasks() async {
    await performBatch(selectedTasks.filter { $0.status == "paused" || $0.status == "waiting" }) { task in
      try await client.unpause(task.id)
    }
  }

  func moveInQueue(_ task: Aria2Task, _ move: QueueMove) async {
    await perform {
      try await client.changePosition(task.id, position: move.position, how: move.how)
    }
  }

  func remove(_ task: Aria2Task, deletingFiles: Bool = false) async {
    guard
      (!deletingFiles && settings.noConfirmBeforeDeleteTask) ||
        TaskRemovalConfirmation.confirm([task], deletingFiles: deletingFiles)
    else {
      return
    }

    await removeTasks([task], deletingFiles: deletingFiles)
    if selectedTaskID == task.id {
      selectedTaskID = nil
    }
  }

  func removeSelectedTasks(deletingFiles: Bool) async {
    let targets = selectedTasks
    guard !targets.isEmpty else { return }
    guard TaskRemovalConfirmation.confirm(targets, deletingFiles: deletingFiles) else { return }
    await removeTasks(targets, deletingFiles: deletingFiles)
    endTaskSelection()
  }

  func clearCompletedTasks() async {
    let completed = tasks.filter { $0.status == "complete" }
    guard !completed.isEmpty, TaskRemovalConfirmation.confirmClearingCompleted(count: completed.count) else {
      return
    }
    await performBatch(completed) { task in
      try await client.removeDownloadResult(task.id)
    }
  }

  func reveal(_ task: Aria2Task) {
    guard let url = task.primaryFileURL else {
      NSWorkspace.shared.open(config.downloadDirectory)
      return
    }

    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func openDownloadDirectory() {
    NSWorkspace.shared.open(config.downloadDirectory)
  }

  func chooseDownloadDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = config.downloadDirectory

    if panel.runModal() == .OK, let url = panel.url {
      settings.downloadDirectory = url.path
    }
  }

  func saveSettings() {
    do {
      let system = settings.systemConfig(basedOn: config.systemConfig)
      let user = settings.userConfig(basedOn: config.userConfig)
      try config.save(system: system, user: user)
      config = config.updating(system: system, user: user)
      settings = SettingsDraft(config: config)
      L10n.configure(language: settings.appLanguage)
      settingsSaved = true

      do {
        try LoginItemManager.apply(settings.openAtLogin)
      } catch {
        let alert = NSAlert(error: error)
        alert.messageText = L10n.tr("login_item.update_failed")
        alert.runModal()
      }

      if settings.taskNotification {
        TaskNotificationManager.requestAuthorization()
      }
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  func testProxy() {
    guard !isTestingProxy else { return }
    isTestingProxy = true
    proxyTestMessage = nil

    let mode = settings.proxyMode
    let scheme = settings.proxyScheme
    let host = settings.proxyHost
    let port = settings.proxyPort
    Task {
      defer { isTestingProxy = false }
      do {
        let result = try await ProxyTestService.test(
          mode: mode,
          scheme: scheme,
          host: host,
          port: port
        )
        guard let proxyAddress = result.proxyAddress else {
          proxyTestMessage = L10n.format(
            "preferences.proxy.test.direct",
            result.directAddress ?? L10n.tr("common.not_found")
          )
          return
        }

        guard let directAddress = result.directAddress else {
          proxyTestMessage = L10n.format("preferences.proxy.test.proxy_only", proxyAddress)
          return
        }

        if proxyAddress == directAddress {
          proxyTestMessage = L10n.format("preferences.proxy.test.same_ip", proxyAddress)
        } else {
          proxyTestMessage = L10n.format(
            "preferences.proxy.test.different_ip",
            directAddress,
            proxyAddress
          )
        }
      } catch {
        proxyTestMessage = L10n.format(
          "preferences.proxy.test.failed",
          error.localizedDescription
        )
      }
    }
  }

  func resetSettings() {
    settings = SettingsDraft(config: config)
    L10n.configure(language: settings.appLanguage)
    settingsSaved = false
    proxyTestMessage = nil
  }

  private func perform(_ operation: () async throws -> Void) async {
    do {
      try await operation()
      await refresh()
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  private func performBatch(
    _ targets: [Aria2Task],
    operation: @MainActor (Aria2Task) async throws -> Void
  ) async {
    guard !targets.isEmpty else { return }
    do {
      for task in targets {
        try await operation(task)
      }
      await refresh()
    } catch {
      NSAlert(error: error).runModal()
      await refresh()
    }
  }

  private func removeTasks(_ targets: [Aria2Task], deletingFiles: Bool) async {
    do {
      for target in targets {
        let files = deletingFiles ? removableFiles(for: target) : []
        if target.status == "complete" || target.status == "error" || target.status == "removed" {
          try await client.removeDownloadResult(target.id)
        } else {
          try await client.remove(target.id)
          try? await Task.sleep(for: .milliseconds(80))
          try? await client.removeDownloadResult(target.id)
        }
        if deletingFiles {
          try moveToTrash(files)
        }
      }
      selectedTaskIDs.subtract(targets.map(\.id))
      await refresh()
    } catch {
      NSAlert(error: error).runModal()
      await refresh()
    }
  }

  private func removableFiles(for task: Aria2Task) -> [URL] {
    let fileManager = FileManager.default
    let downloads = task.fileDetails.map { URL(fileURLWithPath: $0.path) }
    let candidates = Set(downloads).union(CompletedControlFileCleaner.controlFiles(for: task))
    return candidates.filter { fileManager.fileExists(atPath: $0.path) }
  }

  private func moveToTrash(_ urls: [URL]) throws {
    let fileManager = FileManager.default
    for url in urls.sorted(by: { $0.path < $1.path }) {
      try fileManager.trashItem(at: url, resultingItemURL: nil)
    }
  }
}

struct SettingsDraft {
  var downloadDirectory = ""
  var maxOverallDownloadLimit = ""
  var maxOverallUploadLimit = ""
  var maxConcurrentDownloads = 5
  var maxConnectionPerServer = 64
  var split = 64
  var pause = true
  var continueDownloads = true
  var btSaveMetadata = true
  var btForceEncryption = false
  var seedingEnabled = true
  var seedRatio = 1
  var seedTime = 60
  var btTracker = ""
  var rpcPort = 16800
  var rpcSecret = ""
  var listenPort = 21301
  var dhtListenPort = 26701
  var proxyMode = ProxyMode.disabled
  var proxyScheme = ProxyScheme.http
  var proxyHost = ProxyConfiguration.defaultHost
  var proxyPort = ProxyConfiguration.defaultPort
  var openAtLogin = false
  var taskNotification = true
  var noConfirmBeforeDeleteTask = false
  var adaptiveSplits = true
  var adaptiveConnections = true
  var appLanguage = L10n.Language.system.rawValue

  init() {}

  init(config: MotrixConfig) {
    let system = config.systemConfig
    let user = config.userConfig
    downloadDirectory = system["dir"] as? String ?? config.downloadDirectory.path
    maxOverallDownloadLimit = Self.string(system["max-overall-download-limit"], fallback: "0")
    maxOverallUploadLimit = Self.string(system["max-overall-upload-limit"], fallback: "0")
    maxConcurrentDownloads = Self.int(system["max-concurrent-downloads"], fallback: 5)
    maxConnectionPerServer = Aria2Limits.clampConnections(
      Self.int(system["max-connection-per-server"], fallback: Aria2Limits.maximumConnectionsPerServer)
    )
    split = Aria2Limits.clampConnections(
      Self.int(system["split"], fallback: Aria2Limits.maximumConnectionsPerServer)
    )
    pause = Self.bool(system["pause"], fallback: true)
    continueDownloads = Self.bool(system["continue"], fallback: true)
    btSaveMetadata = Self.bool(system["bt-save-metadata"], fallback: true)
    btForceEncryption = Self.bool(system["bt-force-encryption"], fallback: false)
    seedRatio = Self.int(system["seed-ratio"], fallback: 1)
    seedTime = Self.int(system["seed-time"], fallback: 60)
    seedingEnabled = Self.bool(
      user["seeding-enabled"],
      fallback: Self.bool(user["keep-seeding"], fallback: false) || seedTime != 0
    )
    btTracker = system["bt-tracker"] as? String ?? ""
    rpcPort = Self.int(system["rpc-listen-port"], fallback: 16800)
    rpcSecret = system["rpc-secret"] as? String ?? ""
    listenPort = Self.int(system["listen-port"], fallback: 21301)
    dhtListenPort = Self.int(system["dht-listen-port"], fallback: 26701)
    if let rawMode = user["proxy-mode"] as? String {
      proxyMode = ProxyMode(rawValue: rawMode) ?? .disabled
    } else if ProxyConfiguration.hasLegacyProxy(in: system) {
      proxyMode = .manual
    }
    if let legacyEndpoint = ProxyConfiguration.legacyEndpoint(in: system) {
      proxyScheme = legacyEndpoint.scheme
      proxyHost = legacyEndpoint.host
      proxyPort = legacyEndpoint.port
    }
    proxyScheme = ProxyScheme(rawValue: user["proxy-scheme"] as? String ?? "") ?? proxyScheme
    proxyHost = user["proxy-host"] as? String ?? proxyHost
    proxyPort = min(65535, max(1, Self.int(user["proxy-port"], fallback: proxyPort)))
    openAtLogin = Self.bool(user["open-at-login"], fallback: false)
    taskNotification = Self.bool(user["task-notification"], fallback: true)
    noConfirmBeforeDeleteTask = Self.bool(user["no-confirm-before-delete-task"], fallback: false)
    adaptiveSplits = Self.bool(user["adaptive-splits"], fallback: true)
    adaptiveConnections = Self.bool(user["adaptive-connections"], fallback: true)
    appLanguage = user["app-language"] as? String ?? L10n.Language.system.rawValue
  }

  func systemConfig(basedOn base: [String: Any]) -> [String: Any] {
    var result = base
    result["dir"] = downloadDirectory
    result["max-overall-download-limit"] = maxOverallDownloadLimit
    result["max-overall-upload-limit"] = maxOverallUploadLimit
    result["max-concurrent-downloads"] = maxConcurrentDownloads
    result["max-connection-per-server"] = Aria2Limits.clampConnections(maxConnectionPerServer)
    result["split"] = Aria2Limits.clampConnections(split)
    result["pause"] = pause
    result["continue"] = continueDownloads
    result["bt-save-metadata"] = btSaveMetadata
    result["bt-force-encryption"] = btForceEncryption
    result["seed-ratio"] = seedRatio
    result["seed-time"] = seedingEnabled ? seedTime : 0
    result["bt-tracker"] = btTracker
    result["rpc-listen-port"] = rpcPort
    result["rpc-secret"] = rpcSecret
    result["listen-port"] = listenPort
    result["dht-listen-port"] = dhtListenPort
    return result
  }

  func userConfig(basedOn base: [String: Any]) -> [String: Any] {
    var result = base
    result["open-at-login"] = openAtLogin
    result["task-notification"] = taskNotification
    result["no-confirm-before-delete-task"] = noConfirmBeforeDeleteTask
    result["adaptive-splits"] = adaptiveSplits
    result["adaptive-connections"] = adaptiveConnections
    result["app-language"] = appLanguage
    result["seeding-enabled"] = seedingEnabled
    result["proxy-mode"] = proxyMode.rawValue
    result["proxy-scheme"] = proxyScheme.rawValue
    result["proxy-host"] = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
    result["proxy-port"] = min(65535, max(1, proxyPort))
    if !seedingEnabled {
      result["keep-seeding"] = false
    }
    return result
  }

  private static func string(_ value: Any?, fallback: String) -> String {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return fallback
  }

  private static func int(_ value: Any?, fallback: Int) -> Int {
    if let value = value as? Int { return value }
    if let value = value as? String { return Int(value) ?? fallback }
    if let value = value as? NSNumber { return value.intValue }
    return fallback
  }

  private static func bool(_ value: Any?, fallback: Bool) -> Bool {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String { return value == "true" }
    return fallback
  }
}
