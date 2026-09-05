import Foundation

/// One owner for RPC snapshots and history. All mutations and disk writes are
/// serialized on MainActor; views never retain a second writable history cache.
@MainActor
final class TaskSnapshotStore {
  private let client: Aria2RPCClient
  private let history: DownloadHistoryStore
  private var records: [String: DownloadHistoryRecord]
  private var archivedTasks: [String: Aria2Task] = [:]
  private var orderedArchive: [Aria2Task] = []
  private var archiveOrderChanged = true
  private let coalescer = RefreshCoalescer()
  private var observers: [UUID: () -> Void] = [:]
  private var generation = 0
  private var removedIDs = Set<String>()
  private var cleanedIDs = Set<String>()
  private var fileCache: [String: Aria2Task] = [:]
  private var optionLookups = Set<String>()
  private var needsSave = false
  private var historyLoadError: String?
  private var lastRefresh: Date?
  private(set) var liveTasks: [Aria2Task] = []
  private(set) var tasks: [Aria2Task] = []
  private(set) var stat = Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 0, stopped: 0)
  private(set) var errorText: String?
  private(set) var isConnected = false
  var isSuspended = false

  init(config: MotrixConfig, client: Aria2RPCClient) {
    self.client = client
    history = DownloadHistoryStore(supportDirectory: config.supportDirectory)
    records = [:]
    do {
      let saved = try history.loadState()
      records = saved.records
      removedIDs = saved.removedIDs
    } catch {
      historyLoadError = error.localizedDescription
      errorText = L10n.format("history.save_failed", error.localizedDescription)
    }
    for record in records.values where record.isTerminal { archivedTasks[record.id] = record.task() }
    rebuildTasks()
  }

  var pollingInterval: TimeInterval {
    !isConnected || liveTasks.contains { $0.status == "active" || $0.status == "waiting" } ? 2 : 10
  }

  @discardableResult
  func observe(_ action: @escaping () -> Void) -> UUID {
    let id = UUID()
    observers[id] = action
    return id
  }

  func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

  func refresh(queueFollowUp: Bool = true) async {
    guard !isSuspended else { return }
    if !queueFollowUp, let lastRefresh, Date().timeIntervalSince(lastRefresh) < pollingInterval { return }
    await coalescer.run(queueFollowUp: queueFollowUp) { [self] in
      guard !isSuspended else { return }
      let version = generation
      var nextFileCache = fileCache
      do {
        let latestStat = try await client.getGlobalStat()
        let summaries = try await client.listTasks(stat: latestStat, summaryOnly: true)
        var latestTasks: [Aria2Task] = []
        var refreshedFiles = Set<String>()
        for summary in summaries where !removedIDs.contains(summary.id) {
          guard version == generation, !isSuspended else { return }
          let cached = nextFileCache[summary.id]
          if let cached, cached.status == summary.status, cached.totalLength == summary.totalLength {
            latestTasks.append(summary.withCachedFiles(cached))
          } else if summary.isBitTorrent, !summary.isTerminal, cached?.files.isEmpty ?? true {
            // Torrent names are already in the summary. The potentially huge
            // file list is needed only by details/actions or terminal history.
            nextFileCache[summary.id] = summary
            latestTasks.append(summary)
          } else {
            let full = try await client.getTask(summary.id, includeBitfield: false)
            nextFileCache[summary.id] = full
            refreshedFiles.insert(summary.id)
            latestTasks.append(full)
          }
        }
        let summaryIDs = Set(summaries.map(\.id))
        nextFileCache = nextFileCache.filter { summaryIDs.contains($0.key) }
        var checksums: [String: String] = [:]
        var lookedUp = Set<String>()
        for task in latestTasks where !task.isTerminal && !optionLookups.contains(task.id) {
          guard version == generation, !isSuspended else { return }
          if let options = try? await client.getOption(task.id) {
            checksums[task.id] = options["checksum"]
            lookedUp.insert(task.id)
          }
        }
        // A removal or submission while RPC was suspended invalidates this read.
        guard version == generation, !isSuspended else { return }
        fileCache = nextFileCache
        optionLookups.formUnion(lookedUp)
        liveTasks = latestTasks.filter { !removedIDs.contains($0.id) }
        for task in liveTasks {
          let previous = records[task.id]
          if task.isTerminal, previous != nil, !refreshedFiles.contains(task.id) { continue }
          var record: DownloadHistoryRecord
          if let previous, !task.isTerminal {
            record = previous.updatingMetadata(from: task, sourceURI: nil, checksum: checksums[task.id])
          } else {
            record = DownloadHistoryRecord(task: task, existing: previous, checksum: checksums[task.id])
          }
          if lookedUp.contains(task.id) {
            record.checksumKnown = true
            record.checksumResult = ChecksumResult.infer(checksum: record.checksum, status: task.status, errorCode: task.errorCode, errorMessage: task.errorMessage)
          }
          if record != previous {
            records[task.id] = record
            updateArchive(record)
            needsSave = true
          }
        }
        let completed = liveTasks.filter { $0.status == "complete" }
        CompletedControlFileCleaner.clean(tasks: completed.filter { !cleanedIDs.contains($0.id) })
        cleanedIDs = Set(completed.map(\.id))
        stat = latestStat.usingActiveTaskSpeeds(liveTasks)
        isConnected = true
        errorText = nil
        lastRefresh = Date()
        persist()
        rebuildTasks()
      } catch {
        guard version == generation, !isSuspended else { return }
        isConnected = false
        errorText = L10n.tr("engine.rpc_disconnected")
      }
      notify()
    }
  }

  /// Capture submission metadata immediately, including when the next RPC fails.
  func register(_ id: String, sourceURI: String?, checksum: String?) {
    generation += 1
    removedIDs.remove(id)
    let placeholder = Aria2Task.from(["gid": id, "status": "waiting"])!
    let task = liveTasks.first { $0.id == id } ?? records[id]?.task() ?? placeholder
    records[id] = DownloadHistoryRecord(task: task, existing: records[id], sourceURI: sourceURI, checksum: checksum, checksumKnown: true)
    if let record = records[id] { updateArchive(record) }
    needsSave = true
    persist()
    rebuildTasks()
    notify()
  }

  func remove(_ ids: [String]) {
    generation += 1
    removedIDs.formUnion(ids)
    for id in ids {
      records.removeValue(forKey: id)
      archivedTasks.removeValue(forKey: id)
    }
    archiveOrderChanged = true
    liveTasks.removeAll { removedIDs.contains($0.id) }
    needsSave = true
    persist()
    rebuildTasks()
    notify()
  }

  func invalidateFiles(_ id: String) {
    generation += 1
    fileCache.removeValue(forKey: id)
  }

  func decorate(_ task: Aria2Task) -> Aria2Task {
    records[task.id].map(task.applyingHistoryMetadata) ?? task
  }

  func cacheDetails(_ task: Aria2Task) {
    guard !removedIDs.contains(task.id) else { return }
    generation += 1
    fileCache[task.id] = task.withCachedFiles(task)
  }

  func invalidate() {
    generation += 1
    lastRefresh = nil
    fileCache.removeAll()
    optionLookups.removeAll()
  }

  private func persist() {
    // Keep the original file intact for recovery if it cannot be decoded.
    if let historyLoadError {
      errorText = L10n.format("history.save_failed", historyLoadError)
      return
    }
    guard needsSave else { return }
    do {
      try history.save(records, removedIDs: removedIDs)
      needsSave = false
    } catch {
      errorText = L10n.format("history.save_failed", error.localizedDescription)
    }
  }

  private func rebuildTasks() {
    let liveIDs = Set(liveTasks.map(\.id))
    tasks = liveTasks.map(decorate)
    if archiveOrderChanged {
      orderedArchive = archivedTasks.values.sorted {
        if $0.completionDate != $1.completionDate { return ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
        return $0.id < $1.id
      }
      archiveOrderChanged = false
    }
    tasks += orderedArchive.filter { !liveIDs.contains($0.id) }
  }

  private func updateArchive(_ record: DownloadHistoryRecord) {
    if record.isTerminal {
      archivedTasks[record.id] = record.task()
      archiveOrderChanged = true
    } else if archivedTasks.removeValue(forKey: record.id) != nil {
      archiveOrderChanged = true
    }
  }

  private func notify() { for action in observers.values { action() } }
}
