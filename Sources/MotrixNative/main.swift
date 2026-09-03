import AppKit
import Darwin

if CommandLine.arguments.contains("--self-check") {
  let appIdentityReady = Bundle.main.bundleIdentifier == "dev.codex.motrix-native"
    && Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == AppIdentity.displayName
    && Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == AppIdentity.displayName
    && Bundle.main.executableURL?.lastPathComponent == AppIdentity.displayName
  let config = MotrixConfig.load()
  let binaryReady = config.aria2BinaryPath.map {
    FileManager.default.isExecutableFile(atPath: $0.path)
  } ?? false
  let configReady = FileManager.default.fileExists(atPath: config.aria2ConfigPath.path)
  let supportReady = config.supportDirectory.lastPathComponent == "Motrix Native"
  let seedTimeArgument = config.aria2StartArguments().first { $0.hasPrefix("--seed-time=") } ?? ""
  var disabledSeedingUser = config.userConfig
  disabledSeedingUser["seeding-enabled"] = false
  let disabledSeedingArgument = config.updating(user: disabledSeedingUser)
    .aria2StartArguments()
    .first { $0.hasPrefix("--seed-time=") } ?? ""
  let seedingDisableReady = disabledSeedingArgument == "--seed-time=0"
  var manualProxyUser = config.userConfig
  manualProxyUser["proxy-mode"] = ProxyMode.manual.rawValue
  manualProxyUser["proxy-scheme"] = ProxyScheme.http.rawValue
  manualProxyUser["proxy-host"] = "127.0.0.1"
  manualProxyUser["proxy-port"] = 42613
  let manualProxyArguments = Set(config.updating(user: manualProxyUser).aria2StartArguments())
  var disabledProxyUser = manualProxyUser
  disabledProxyUser["proxy-mode"] = ProxyMode.disabled.rawValue
  let disabledProxyArguments = config.updating(user: disabledProxyUser).aria2StartArguments()
  let proxyArgumentsReady = manualProxyArguments.contains("--all-proxy=http://127.0.0.1:42613")
    && manualProxyArguments.contains("--no-proxy=localhost,127.0.0.1,::1")
    && !disabledProxyArguments.contains { argument in
      argument.hasPrefix("--all-proxy=")
        || argument.hasPrefix("--http-proxy=")
        || argument.hasPrefix("--https-proxy=")
    }
  var oversizedConnectionSystem = config.systemConfig
  oversizedConnectionSystem["max-connection-per-server"] = 128
  oversizedConnectionSystem["split"] = 128
  let oversizedConnectionConfig = config.updating(system: oversizedConnectionSystem)
  let oversizedConnectionArguments = Set(oversizedConnectionConfig.aria2StartArguments())
  let adaptiveLimitReady = oversizedConnectionConfig.adaptiveConnectionCeiling == 64
    && Aria2Limits.clampConnections(0) == 1
    && Aria2Limits.clampConnections(128) == 64
    && oversizedConnectionArguments.contains("--max-connection-per-server=64")
    && oversizedConnectionArguments.contains("--split=64")
  let adaptiveProfileLimitReady: Bool = {
    let profileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("motrix-native-adaptive-check-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: profileURL) }

    AdaptiveConnectionProfileStore.save(["example.invalid": 128], to: profileURL)
    return AdaptiveConnectionProfileStore.load(from: profileURL)["example.invalid"] == 64
  }()
  let adaptiveStartReady = config.adaptiveStartingConnections == min(48, config.adaptiveConnectionCeiling)
    && config.adaptiveConnectionCeiling <= Aria2Limits.maximumConnectionsPerServer
  var decoupledAdaptiveSystem = config.systemConfig
  decoupledAdaptiveSystem["max-connection-per-server"] = 32
  decoupledAdaptiveSystem["split"] = 64
  var decoupledAdaptiveUser = config.userConfig
  decoupledAdaptiveUser["adaptive-connections"] = false
  decoupledAdaptiveUser["adaptive-splits"] = true
  let decoupledAdaptiveConfig = config.updating(
    system: decoupledAdaptiveSystem,
    user: decoupledAdaptiveUser
  )
  let adaptiveModesReady = decoupledAdaptiveConfig.adaptiveConnectionCeiling == 32
    && decoupledAdaptiveConfig.adaptiveSplitCeiling == 64
    && !decoupledAdaptiveConfig.adaptiveConnectionsEnabled
    && decoupledAdaptiveConfig.adaptiveSplitsEnabled
  let taskTuningURI = "https://motrix-native-self-check.invalid/archive.bin"
  let splitOnlyOptions = decoupledAdaptiveConfig.adaptiveTaskOptions(for: taskTuningURI)
  decoupledAdaptiveUser["adaptive-connections"] = true
  decoupledAdaptiveUser["adaptive-splits"] = false
  let connectionOnlyOptions = config.updating(
    system: decoupledAdaptiveSystem,
    user: decoupledAdaptiveUser
  ).adaptiveTaskOptions(for: taskTuningURI)
  decoupledAdaptiveUser["adaptive-connections"] = true
  decoupledAdaptiveUser["adaptive-splits"] = true
  let bothAdaptiveOptions = config.updating(
    system: decoupledAdaptiveSystem,
    user: decoupledAdaptiveUser
  ).adaptiveTaskOptions(for: taskTuningURI)
  decoupledAdaptiveUser["adaptive-connections"] = false
  decoupledAdaptiveUser["adaptive-splits"] = false
  let fixedOptions = config.updating(
    system: decoupledAdaptiveSystem,
    user: decoupledAdaptiveUser
  ).adaptiveTaskOptions(for: taskTuningURI)
  let adaptiveCombinationsReady = Set(splitOnlyOptions.keys) == ["split"]
    && Set(connectionOnlyOptions.keys) == ["max-connection-per-server"]
    && Set(bothAdaptiveOptions.keys) == ["split", "max-connection-per-server"]
    && fixedOptions.isEmpty
  let mebibyte = Int64(1024 * 1024)
  let gibibyte = Int64(1024 * 1024 * 1024)
  let adaptiveSplitReady = AdaptiveSplitPolicy.initialSplit(limit: 64) == 8
    && AdaptiveSplitPolicy.recommendedSplit(totalLength: 16 * mebibyte, limit: 64) == 1
    && AdaptiveSplitPolicy.recommendedSplit(totalLength: 64 * mebibyte, limit: 64) == 4
    && AdaptiveSplitPolicy.recommendedSplit(totalLength: 256 * mebibyte, limit: 64) == 8
    && AdaptiveSplitPolicy.recommendedSplit(totalLength: 1 * gibibyte, limit: 64) == 16
    && AdaptiveSplitPolicy.recommendedSplit(totalLength: 4 * gibibyte, limit: 64) == 32
    && AdaptiveSplitPolicy.recommendedSplit(totalLength: 16 * gibibyte, limit: 64) == 48
    && AdaptiveSplitPolicy.recommendedSplit(totalLength: 64 * gibibyte, limit: 64) == 64
    && AdaptiveSplitPolicy.recommendedSplit(totalLength: 64 * gibibyte, limit: 24) == 24
  let syntheticTorrent = Aria2Task(
    id: "self-check",
    status: "complete",
    totalLength: 1,
    completedLength: 1,
    uploadLength: 0,
    downloadSpeed: 0,
    uploadSpeed: 0,
    connections: 0,
    pieceLength: 1,
    numPieces: 1,
    bitfield: "8",
    errorCode: "0",
    errorMessage: "",
    directory: "/tmp/downloads",
    bitTorrentName: "Example",
    infoHash: "",
    trackers: [],
    files: [],
    isBitTorrent: true
  )
  let controlFileMappingReady = CompletedControlFileCleaner.controlFiles(for: syntheticTorrent)
    .contains(URL(fileURLWithPath: "/tmp/downloads/Example.aria2"))
  let pieceBitfieldReady = syntheticTorrent.pieceCompletion == [true]
  let trackerNormalizationReady = TrackerList.aria2Value(
    from: "udp://tracker.example:80/announce\nhttps://tracker.example/announce\nwss://unsupported.example/announce"
  ) == "udp://tracker.example:80/announce,https://tracker.example/announce"
  let configuredTrackerValue = config.systemConfig["bt-tracker"] as? String ?? ""
  let configuredTrackerArgument = config.aria2StartArguments().first { $0.hasPrefix("--bt-tracker=") } ?? ""
  let configuredTrackerArgumentReady = !configuredTrackerArgument.contains("\n") && !configuredTrackerArgument.contains("wss://")
  let loggingArguments = Set(config.aria2StartArguments().filter {
    $0.hasPrefix("--log=")
      || $0.hasPrefix("--log-level=")
      || $0.hasPrefix("--quiet=")
      || $0.hasPrefix("--show-console-readout=")
      || $0.hasPrefix("--enable-color=")
  })
  let cleanFileLoggingReady = loggingArguments == [
    "--log=\(config.aria2LogPath.path)",
    "--log-level=notice",
    "--quiet=true",
    "--show-console-readout=false",
    "--enable-color=false"
  ]
  let logRotationReady: Bool = {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("motrix-native-log-check-\(UUID().uuidString)", isDirectory: true)
    let activeURL = directory.appendingPathComponent("aria2.log")
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let original = Data(repeating: 65, count: 65)
      try original.write(to: activeURL)
      let store = Aria2LogStore(activeURL: activeURL, maximumFileSize: 64, retainedArchiveCount: 2)
      store.rotateIfNeeded()
      let activeSize = try Data(contentsOf: activeURL).count
      let archived = try Data(contentsOf: store.archiveURL(index: 1))
      return activeSize == 0 && archived == original
    } catch {
      return false
    }
  }()
  let localizationReady: Bool = {
    let key = "action.cancel"
    let values = ["zh-Hans", "en"].compactMap { language -> String? in
      guard
        let path = Bundle.main.path(forResource: language, ofType: "lproj"),
        let bundle = Bundle(path: path)
      else {
        return nil
      }
      return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    return values.count == 2 && values.allSatisfy { $0 != key } && values[0] != values[1]
  }()
  let languageSwitchReady: Bool = {
    defer { L10n.configure(language: config.appLanguage) }
    L10n.configure(language: L10n.Language.english.rawValue)
    let english = L10n.tr("action.cancel")
    L10n.configure(language: L10n.Language.simplifiedChinese.rawValue)
    let simplifiedChinese = L10n.tr("action.cancel")
    return english != "action.cancel" && simplifiedChinese != "action.cancel" && english != simplifiedChinese
  }()
  let aria2Build = Aria2BuildInfo.load()
  let aria2VersionOutput = config.aria2BinaryPath.flatMap(Aria2BinaryInspector.versionOutput)
  let aria2Architectures = config.aria2BinaryPath.flatMap(Aria2BinaryInspector.architectures) ?? ""
  let aria2ConnectionLimitReady = config.aria2BinaryPath.map {
    Aria2BinaryInspector.acceptsConnectionLimit(at: $0, limit: 64)
  } ?? false
  let aria2BuildReady = aria2Build?.architecture == "arm64"
    && aria2Build?.aria2Commit == "9e7273583f83e881e3ec067b523ba88724088d2f"
    && aria2Build?.aria2Version == "1.37.0-git.9e72735"
    && aria2Build?.compatibility.maxConnectionsPerServer == 64
    && aria2Build?.tlsBackend == "AppleTLS"
    && aria2Architectures == "arm64"
    && aria2ConnectionLimitReady
    && aria2VersionOutput?.contains("aria2 version 1.37.0-git.9e72735") == true
  let result: [String: Any] = [
    "appName": AppIdentity.displayName,
    "appIdentityReady": appIdentityReady,
    "aria2Binary": config.aria2BinaryPath?.path ?? "",
    "aria2BinaryReady": binaryReady,
    "aria2Architecture": aria2Architectures,
    "aria2BuildReady": aria2BuildReady,
    "aria2ConnectionLimitReady": aria2ConnectionLimitReady,
    "aria2Commit": aria2Build?.aria2Commit ?? "",
    "aria2Version": aria2Build?.aria2Version ?? "",
    "aria2Config": config.aria2ConfigPath.path,
    "aria2ConfigReady": configReady,
    "adaptiveConnectionCeiling": config.adaptiveConnectionCeiling,
    "adaptiveStartingConnections": config.adaptiveStartingConnections,
    "adaptiveLimitReady": adaptiveLimitReady,
    "adaptiveModesReady": adaptiveModesReady,
    "adaptiveCombinationsReady": adaptiveCombinationsReady,
    "adaptiveProfileLimitReady": adaptiveProfileLimitReady,
    "adaptiveSplitReady": adaptiveSplitReady,
    "adaptiveStartReady": adaptiveStartReady,
    "rpcPort": config.rpcPort,
    "seedTimeArgument": seedTimeArgument,
    "seedingDisableReady": seedingDisableReady,
    "session": config.sessionPath.path,
    "supportDirectory": config.supportDirectory.path,
    "supportDirectoryReady": supportReady,
    "controlFileMappingReady": controlFileMappingReady,
    "pieceBitfieldReady": pieceBitfieldReady,
    "proxyArgumentsReady": proxyArgumentsReady,
    "trackerNormalizationReady": trackerNormalizationReady,
    "configuredTrackerArgumentReady": configuredTrackerArgumentReady,
    "cleanFileLoggingReady": cleanFileLoggingReady,
    "logRotationReady": logRotationReady,
    "localizationReady": localizationReady,
    "languageSwitchReady": languageSwitchReady,
    "configuredTrackerCount": TrackerList.supportedEntries(from: configuredTrackerValue).count,
    "ignoredTrackerCount": TrackerList.unsupportedEntries(from: configuredTrackerValue).count
  ]
  let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
  exit(appIdentityReady && binaryReady && aria2BuildReady && configReady && supportReady && controlFileMappingReady && pieceBitfieldReady && trackerNormalizationReady && configuredTrackerArgumentReady && cleanFileLoggingReady && logRotationReady && localizationReady && languageSwitchReady && seedingDisableReady && adaptiveStartReady && adaptiveLimitReady && adaptiveProfileLimitReady && adaptiveModesReady && adaptiveCombinationsReady && adaptiveSplitReady && proxyArgumentsReady ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
