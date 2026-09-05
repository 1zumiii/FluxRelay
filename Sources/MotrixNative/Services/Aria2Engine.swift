import Foundation

@MainActor
final class Aria2Engine {
  private var config: MotrixConfig
  private var process: Process?
  private var lastStartAttempt: Date?
  private var lastLogMaintenance: Date?
  private var consecutiveFailures = 0

  private(set) var statusText = L10n.tr("engine.not_started")
  private(set) var lastError: String?

  init(config: MotrixConfig) {
    self.config = config
  }

  func updateConfig(_ config: MotrixConfig) {
    self.config = config
  }

  func ensureRunning(client: Aria2RPCClient, force: Bool = false) async {
    maintainLogSize()
    if await canConnect(client: client) {
      statusText = L10n.tr("engine.rpc_connected")
      consecutiveFailures = 0
      lastError = nil
      return
    }

    guard force || shouldAttemptStart() else {
      return
    }

    startBundledAria2()

    for _ in 0..<15 {
      try? await Task.sleep(for: .milliseconds(200))
      if await canConnect(client: client) {
        statusText = L10n.tr("engine.rpc_connected")
        consecutiveFailures = 0
        lastError = nil
        return
      }
    }

    statusText = L10n.tr("engine.rpc_disconnected")
  }

  func stop() {
    guard let process, process.isRunning else {
      return
    }

    process.terminate()
  }

  func stopGracefully(client: Aria2RPCClient) async {
    guard let ownedProcess = process, ownedProcess.isRunning else {
      return
    }

    statusText = L10n.tr("engine.saving_tasks")
    try? await client.saveSession()
    try? await client.shutdown()

    for _ in 0..<15 where ownedProcess.isRunning {
      try? await Task.sleep(for: .milliseconds(100))
    }

    if ownedProcess.isRunning {
      appendLog("aria2 did not exit after RPC shutdown; terminating the owned process.")
      ownedProcess.terminate()
    }
  }

  func restart(client: Aria2RPCClient, config nextConfig: MotrixConfig) async -> Bool {
    // Never report that an external engine was restarted, or switch credentials
    // before saving the session through the endpoint that owns the running job.
    if let ownedProcess = process, ownedProcess.isRunning {
      do {
        try await client.saveSession()
        try await client.shutdown()
      } catch {
        lastError = error.localizedDescription
        return false
      }
      for _ in 0..<40 where ownedProcess.isRunning {
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard !ownedProcess.isRunning else {
        lastError = L10n.tr("preferences.restart_failed")
        return false
      }
    } else if await canConnect(client: client) {
      lastError = L10n.tr("preferences.restart_failed")
      return false
    }
    process = nil
    consecutiveFailures = 0
    lastStartAttempt = nil
    config = nextConfig
    client.updateConfig(nextConfig)
    startBundledAria2()
    guard let startedProcess = process else { return false }
    for _ in 0..<25 {
      try? await Task.sleep(for: .milliseconds(200))
      guard startedProcess.isRunning else { return false }
      if await canConnect(client: client) {
        statusText = L10n.tr("engine.rpc_connected")
        lastError = nil
        return true
      }
    }
    return false
  }

  private func canConnect(client: Aria2RPCClient) async -> Bool {
    do {
      _ = try await client.getGlobalStat()
      return true
    } catch {
      return false
    }
  }

  private func startBundledAria2() {
    guard let binary = config.aria2BinaryPath else {
      statusText = L10n.tr("engine.binary_missing")
      lastError = L10n.tr("engine.binary_not_found")
      return
    }

    lastStartAttempt = Date()
    statusText = L10n.tr("engine.starting")

    let fileManager = FileManager.default
    try? fileManager.createDirectory(at: config.supportDirectory, withIntermediateDirectories: true)

    let process = Process()
    let diagnosticsPipe = Pipe()
    process.executableURL = binary
    process.currentDirectoryURL = config.supportDirectory
    process.arguments = config.aria2StartArguments()
    process.terminationHandler = { [weak self] process in
      let diagnostics = String(
        data: diagnosticsPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? ""
      Task { @MainActor in
        self?.handleProcessExit(process, diagnostics: diagnostics)
      }
    }
    let logURL = config.aria2LogPath
    Aria2LogStore(activeURL: logURL).prepare()
    lastLogMaintenance = Date()
    if !fileManager.fileExists(atPath: logURL.path) {
      fileManager.createFile(atPath: logURL.path, contents: nil)
    }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = diagnosticsPipe

    do {
      try process.run()
      self.process = process
      appendLog("\(AppIdentity.displayName) launched aria2c with \(process.arguments?.count ?? 0) arguments.")
    } catch {
      consecutiveFailures += 1
      statusText = L10n.tr("engine.start_failed")
      lastError = error.localizedDescription
      appendLog("\(AppIdentity.displayName) failed to launch aria2c: \(error.localizedDescription)")
      self.process = nil
    }
  }

  private func shouldAttemptStart() -> Bool {
    if let process, process.isRunning {
      return false
    }

    guard let lastStartAttempt else {
      return true
    }

    let delay = min(30, max(2, 1 << min(consecutiveFailures, 5)))
    return Date().timeIntervalSince(lastStartAttempt) >= TimeInterval(delay)
  }

  private func handleProcessExit(_ process: Process, diagnostics: String) {
    guard self.process === process else {
      return
    }

    self.process = nil
    if process.terminationStatus == 0 {
      statusText = L10n.tr("engine.exited")
      return
    }

    consecutiveFailures += 1
    statusText = L10n.tr("engine.crashed")
    let normalizedDiagnostics = diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedDiagnostics.isEmpty {
      appendLog("aria2 exited with status \(process.terminationStatus):\n\(String(normalizedDiagnostics.prefix(4096)))")
    }
    let firstDiagnosticLine = normalizedDiagnostics
      .split(whereSeparator: { $0.isNewline })
      .first
      .map(String.init)
    lastError = firstDiagnosticLine ?? "exit \(process.terminationStatus)"
  }

  private func appendLog(_ message: String) {
    let line = "[\(AppIdentity.displayName) \(Date())] \(message)\n"
    guard let data = line.data(using: .utf8) else {
      return
    }

    if !FileManager.default.fileExists(atPath: config.aria2LogPath.path) {
      FileManager.default.createFile(atPath: config.aria2LogPath.path, contents: nil)
    }

    guard let handle = try? FileHandle(forWritingTo: config.aria2LogPath) else {
      return
    }

    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: data)
    try? handle.close()
  }

  private func maintainLogSize() {
    let now = Date()
    if let lastLogMaintenance, now.timeIntervalSince(lastLogMaintenance) < 60 {
      return
    }

    lastLogMaintenance = now
    Aria2LogStore(activeURL: config.aria2LogPath).rotateIfNeeded()
  }
}
