import Foundation

struct MotrixConfig {
  let supportDirectory: URL
  let rpcPort: Int
  let rpcSecret: String
  let downloadDirectory: URL
  let sessionPath: URL
  let aria2ConfigPath: URL
  let aria2BinaryPath: URL?
  let aria2LogPath: URL
  let systemConfig: [String: Any]
  let userConfig: [String: Any]

  var adaptiveConnectionsEnabled: Bool {
    if let value = userConfig["adaptive-connections"] as? Bool {
      return value
    }
    if let value = userConfig["adaptive-connections"] as? NSNumber {
      return value.boolValue
    }
    return true
  }

  var adaptiveSplitsEnabled: Bool {
    if let value = userConfig["adaptive-splits"] as? Bool {
      return value
    }
    if let value = userConfig["adaptive-splits"] as? NSNumber {
      return value.boolValue
    }
    return true
  }

  var openAtLoginEnabled: Bool {
    boolValue(userConfig["open-at-login"]) ?? false
  }

  var appLanguage: String {
    userConfig["app-language"] as? String ?? L10n.Language.system.rawValue
  }

  var taskNotificationsEnabled: Bool {
    boolValue(userConfig["task-notification"]) ?? true
  }

  var skipsRemovalConfirmation: Bool {
    boolValue(userConfig["no-confirm-before-delete-task"]) ?? false
  }

  var adaptiveConnectionCeiling: Int {
    let perServer = intValue(systemConfig["max-connection-per-server"]) ?? 64
    return Aria2Limits.clampConnections(perServer)
  }

  var adaptiveSplitCeiling: Int {
    Aria2Limits.clampConnections(intValue(systemConfig["split"]) ?? 64)
  }

  var adaptiveStartingConnections: Int {
    min(48, adaptiveConnectionCeiling)
  }

  var adaptiveInitialSplit: Int {
    AdaptiveSplitPolicy.initialSplit(limit: adaptiveSplitCeiling)
  }

  var adaptiveProfilePath: URL {
    supportDirectory.appendingPathComponent("adaptive-hosts-v2.json")
  }

  func adaptiveTaskOptions(for uri: String) -> [String: String] {
    var options: [String: String] = [:]

    if adaptiveSplitsEnabled {
      options["split"] = "\(adaptiveInitialSplit)"
    }

    if adaptiveConnectionsEnabled, let host = URL(string: uri)?.host?.lowercased() {
      let learned = AdaptiveConnectionProfileStore.load(from: adaptiveProfilePath)[host]
      let connections = Aria2Limits.clampConnections(
        min(adaptiveConnectionCeiling, learned ?? adaptiveStartingConnections)
      )
      options["max-connection-per-server"] = "\(connections)"
    }

    return options
  }

  private static let numericAria2Options: Set<String> = [
    "dht-listen-port",
    "listen-port",
    "max-concurrent-downloads",
    "max-connection-per-server",
    "max-download-limit",
    "max-overall-download-limit",
    "max-overall-upload-limit",
    "seed-ratio",
    "seed-time",
    "split"
  ]

  private static let booleanAria2Options: Set<String> = [
    "allow-overwrite",
    "auto-file-renaming",
    "bt-force-encryption",
    "bt-load-saved-metadata",
    "bt-save-metadata",
    "continue",
    "enable-dht6",
    "follow-metalink",
    "follow-torrent",
    "pause",
    "pause-metadata"
  ]

  static func load() -> MotrixConfig {
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser
    let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? home.appendingPathComponent("Library/Application Support")
    // Keep the existing data location when upgrading from Motrix Native to FluxRelay.
    let supportDirectory = applicationSupport.appendingPathComponent("Motrix Native", isDirectory: true)
    let legacySupportDirectory = applicationSupport.appendingPathComponent("Motrix", isDirectory: true)

    try? fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    migrateLegacyDataIfNeeded(from: legacySupportDirectory, to: supportDirectory)

    let system = readJSON(supportDirectory.appendingPathComponent("system.json"))
    let user = readJSON(supportDirectory.appendingPathComponent("user.json"))
    let rpcPort = system["rpc-listen-port"] as? Int ?? 16800
    let rpcSecret = system["rpc-secret"] as? String ?? ""

    let defaultDownloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Downloads")
    let dir = system["dir"] as? String
    let downloadDirectory = dir.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? defaultDownloads

    let sessionPath = supportDirectory.appendingPathComponent("download.session")
    let aria2ConfigPath = bundledAria2Config() ?? supportDirectory.appendingPathComponent("aria2.conf")

    return MotrixConfig(
      supportDirectory: supportDirectory,
      rpcPort: rpcPort,
      rpcSecret: rpcSecret,
      downloadDirectory: downloadDirectory,
      sessionPath: sessionPath,
      aria2ConfigPath: aria2ConfigPath,
      aria2BinaryPath: bundledAria2Binary(),
      aria2LogPath: supportDirectory.appendingPathComponent("motrix-native-aria2.log"),
      systemConfig: system,
      userConfig: user
    )
  }

  func updating(system: [String: Any]? = nil, user: [String: Any]? = nil) -> MotrixConfig {
    MotrixConfig(
      supportDirectory: supportDirectory,
      rpcPort: (system ?? systemConfig)["rpc-listen-port"] as? Int ?? rpcPort,
      rpcSecret: (system ?? systemConfig)["rpc-secret"] as? String ?? rpcSecret,
      downloadDirectory: ((system ?? systemConfig)["dir"] as? String)
        .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? downloadDirectory,
      sessionPath: sessionPath,
      aria2ConfigPath: aria2ConfigPath,
      aria2BinaryPath: aria2BinaryPath,
      aria2LogPath: aria2LogPath,
      systemConfig: system ?? systemConfig,
      userConfig: user ?? userConfig
    )
  }

  func save(system: [String: Any]? = nil, user: [String: Any]? = nil) throws {
    if let system {
      try saveJSON(system, to: supportDirectory.appendingPathComponent("system.json"))
    }

    if let user {
      try saveJSON(user, to: supportDirectory.appendingPathComponent("user.json"))
    }
  }

  func aria2StartArguments() -> [String] {
    var arguments = [
      "--conf-path=\(aria2ConfigPath.path)",
      "--save-session=\(sessionPath.path)",
      "--log=\(aria2LogPath.path)",
      "--log-level=notice",
      "--quiet=true",
      "--show-console-readout=false",
      "--enable-color=false"
    ]

    if FileManager.default.fileExists(atPath: sessionPath.path) {
      arguments.append("--input-file=\(sessionPath.path)")
    }

    var engineConfig = systemConfig
    // Older Motrix configurations disabled TLS verification globally. Do not
    // carry that insecure default into the independent engine.
    engineConfig["check-certificate"] = "true"
    for key in ["log", "log-level", "quiet", "show-console-readout", "enable-color"] {
      engineConfig.removeValue(forKey: key)
    }
    engineConfig["max-connection-per-server"] = Aria2Limits.clampConnections(
      intValue(engineConfig["max-connection-per-server"]) ?? Aria2Limits.maximumConnectionsPerServer
    )
    engineConfig["split"] = Aria2Limits.clampConnections(
      intValue(engineConfig["split"]) ?? Aria2Limits.maximumConnectionsPerServer
    )
    ProxyConfiguration.apply(to: &engineConfig, userConfig: userConfig)
    let seedingEnabled = boolValue(userConfig["seeding-enabled"])
      ?? ((intValue(engineConfig["seed-time"]) ?? 60) != 0)
    if !seedingEnabled {
      engineConfig["seed-time"] = 0
    } else if boolValue(userConfig["keep-seeding"]) == true {
      engineConfig["seed-ratio"] = 0
      engineConfig.removeValue(forKey: "seed-time")
    }

    arguments.append(contentsOf: engineConfig.compactMap(Self.argument).sorted())

    arguments.append("--enable-rpc=true")
    arguments.append("--rpc-listen-all=false")
    arguments.append("--rpc-listen-port=\(rpcPort)")

    if !rpcSecret.isEmpty {
      arguments.append("--rpc-secret=\(rpcSecret)")
    }

    arguments.append("--dir=\(downloadDirectory.path)")
    arguments.append("--save-session=\(sessionPath.path)")

    return arguments
  }

  private func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
      return value
    }

    if let value = value as? String {
      return Int(value)
    }

    return nil
  }

  private func boolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
      return value
    }
    if let value = value as? NSNumber {
      return value.boolValue
    }
    if let value = value as? String {
      return value == "true"
    }
    return nil
  }

  private static func argument(key: String, value: Any) -> String? {
    if key == "bt-tracker", let rawValue = value as? String {
      let normalized = TrackerList.aria2Value(from: rawValue)
      return normalized.isEmpty ? nil : "--bt-tracker=\(normalized)"
    }

    if numericAria2Options.contains(key) {
      guard let value = numericString(value) else {
        return nil
      }
      return "--\(key)=\(value)"
    }

    if booleanAria2Options.contains(key) {
      guard let value = boolString(value) else {
        return nil
      }
      return "--\(key)=\(value)"
    }

    if let value = value as? String {
      guard !value.isEmpty else {
        return nil
      }
      return "--\(key)=\(value)"
    }

    return nil
  }

  private static func numericString(_ value: Any) -> String? {
    if let value = value as? String {
      return value.isEmpty ? nil : value
    }

    if let value = value as? Int {
      return "\(value)"
    }

    if let value = value as? Double {
      return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : "\(value)"
    }

    if let value = value as? NSNumber {
      return value.stringValue
    }

    return nil
  }

  private static func boolString(_ value: Any) -> String? {
    if let value = value as? Bool {
      return value ? "true" : "false"
    }

    if let value = value as? String {
      return value.isEmpty ? nil : value
    }

    if let value = value as? NSNumber {
      return value.boolValue ? "true" : "false"
    }

    return nil
  }

  private static func readJSON(_ url: URL) -> [String: Any] {
    guard
      let data = try? Data(contentsOf: url),
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else {
      return [:]
    }

    return dictionary
  }

  private func saveJSON(_ dictionary: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
  }

  private static func migrateLegacyDataIfNeeded(from legacyDirectory: URL, to nativeDirectory: URL) {
    let fileManager = FileManager.default
    let marker = nativeDirectory.appendingPathComponent(".motrix-migration-complete")
    guard !fileManager.fileExists(atPath: marker.path) else {
      return
    }

    for filename in ["system.json", "user.json"] {
      let source = legacyDirectory.appendingPathComponent(filename)
      let destination = nativeDirectory.appendingPathComponent(filename)
      guard
        fileManager.fileExists(atPath: source.path),
        !fileManager.fileExists(atPath: destination.path)
      else {
        continue
      }

      try? fileManager.copyItem(at: source, to: destination)
    }

    let legacySession = legacyDirectory.appendingPathComponent("download.session")
    let nativeSession = nativeDirectory.appendingPathComponent("download.session")
    if fileManager.fileExists(atPath: legacySession.path) {
      let legacyDate = (try? legacySession.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
      let nativeDate = (try? nativeSession.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
      if !fileManager.fileExists(atPath: nativeSession.path) || legacyDate > nativeDate {
        let temporary = nativeDirectory.appendingPathComponent("download.session.importing")
        try? fileManager.removeItem(at: temporary)
        do {
          try fileManager.copyItem(at: legacySession, to: temporary)
        } catch {
          return
        }
        _ = try? fileManager.replaceItemAt(nativeSession, withItemAt: temporary)
        if !fileManager.fileExists(atPath: nativeSession.path) {
          try? fileManager.moveItem(at: temporary, to: nativeSession)
        }
      }
    }

    try? Data().write(to: marker, options: .atomic)
  }

  private static func bundledAria2Binary() -> URL? {
    resourceCandidates(named: "aria2c")
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  private static func bundledAria2Config() -> URL? {
    resourceCandidates(named: "aria2.conf")
      .first { FileManager.default.fileExists(atPath: $0.path) }
  }

  private static func resourceCandidates(named name: String) -> [URL] {
    guard let resourceURL = Bundle.main.resourceURL else {
      return []
    }

    return [
      resourceURL.appendingPathComponent("engine").appendingPathComponent(name),
      resourceURL.appendingPathComponent(name)
    ]
  }
}

extension ProcessInfo {
  var machineHardwareName: String {
    var size = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    var machine = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.machine", &machine, &size, nil, 0)
    return String(decoding: machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
