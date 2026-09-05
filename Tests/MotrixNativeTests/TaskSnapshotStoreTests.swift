import Foundation
import XCTest
@testable import MotrixNative

@MainActor
final class TaskSnapshotStoreTests: XCTestCase {
  private var directory: URL!
  private var config: MotrixConfig!
  private var client: Aria2RPCClient!

  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    config = MotrixConfig(supportDirectory: directory, rpcPort: 16800, rpcSecret: "",
      downloadDirectory: directory, sessionPath: directory.appendingPathComponent("session"),
      aria2ConfigPath: directory.appendingPathComponent("aria2.conf"), aria2BinaryPath: nil,
      aria2LogPath: directory.appendingPathComponent("aria2.log"),
      systemConfig: ["rpc-listen-port": 16800], userConfig: [:])
    let session = URLSessionConfiguration.ephemeral
    session.protocolClasses = [RPCMock.self]
    client = Aria2RPCClient(config: config, session: URLSession(configuration: session))
  }

  override func tearDown() async throws {
    try FileManager.default.removeItem(at: directory)
  }

  private func task(_ status: String) -> [String: Any] {
    ["gid": "abc", "status": status, "totalLength": "100", "completedLength": status == "complete" ? "100" : "1",
     "files": [["index": "1", "path": directory.appendingPathComponent("file.zip").path,
                "length": "100", "completedLength": "100", "uris": [["uri": "https://example.test/file.zip"]]]]]
  }

  private func installTask(_ status: String) -> () -> [String] {
    RPCMock.install { [self] method, params in
      switch method {
      case "aria2.getGlobalStat": return ["numActive": status == "active" ? "1" : "0", "numStopped": status == "complete" ? "1" : "0"]
      case "aria2.tellActive":
        XCTAssertFalse((params.first as? [String] ?? []).contains("files"))
        XCTAssertFalse((params.first as? [String] ?? []).contains("bitfield"))
        return status == "active" ? [task(status)] : []
      case "aria2.tellStopped": return [task(status)]
      case "aria2.tellStatus":
        XCTAssertFalse((params[1] as? [String] ?? []).contains("bitfield"))
        return task(status)
      case "aria2.getOption": return ["checksum": "sha-256=abc"]
      default: throw RPCMockFailure(message: "Unexpected \(method)")
      }
    }
  }

  func testTwoWindowsShareSnapshotAndIdlePollingSkipsRPC() async {
    let requests = installTask("complete")
    let store = TaskSnapshotStore(config: config, client: client)
    let first = MainWindowModel(config: config, client: client, snapshots: store)
    let second = MainWindowModel(config: config, client: client, snapshots: store)
    await store.refresh()
    XCTAssertEqual(first.tasks.map(\.id), ["abc"])
    XCTAssertEqual(second.tasks.map(\.id), ["abc"])
    XCTAssertEqual(requests().filter { $0 == "aria2.getGlobalStat" }.count, 1)
    XCTAssertEqual(store.pollingInterval, 10)
    await first.refresh(queueFollowUp: false)
    await second.refresh(queueFollowUp: false)
    XCTAssertEqual(requests().filter { $0 == "aria2.getGlobalStat" }.count, 1)
    await store.refresh()
    XCTAssertEqual(requests().filter { $0 == "aria2.tellStatus" }.count, 1, "File metadata should be cached")
  }

  func testOfflineStartupLoadsSearchableHistoryAndDeletionIsShared() async throws {
    _ = installTask("active")
    let store = TaskSnapshotStore(config: config, client: client)
    store.register("abc", sourceURI: "https://source.test/archive", checksum: "sha-256=abc")
    await store.refresh()
    XCTAssertEqual(store.pollingInterval, 2)
    _ = installTask("complete")
    await store.refresh()
    let date = try XCTUnwrap(store.tasks.first?.completionDate)
    let restarted = TaskSnapshotStore(config: config, client: client)
    let model = MainWindowModel(config: config, client: client, snapshots: restarted)
    XCTAssertEqual(model.tasks.count, 1)
    XCTAssertEqual(model.tasks.first?.checksumResult, .passed)
    XCTAssertEqual(model.tasks.first?.completionDate?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1)
    model.searchText = "source.test"
    XCTAssertEqual(model.filteredTasks.count, 1)
    restarted.remove(["abc"])
    XCTAssertTrue(model.tasks.isEmpty)
    await restarted.refresh() // aria2 still returning a stale removed result
    XCTAssertTrue(model.tasks.isEmpty)
    XCTAssertTrue(try DownloadHistoryStore(supportDirectory: directory).loadChecked().isEmpty)
    let thirdLaunch = TaskSnapshotStore(config: config, client: client)
    await thirdLaunch.refresh()
    XCTAssertTrue(thirdLaunch.tasks.isEmpty, "Deleted external-engine results must stay deleted after relaunch")
  }

  func testRemovalDuringRPCDoesNotResurrectHistory() async {
    let store = TaskSnapshotStore(config: config, client: client)
    _ = RPCMock.install { [self] method, _ in
      switch method {
      case "aria2.getGlobalStat": return ["numStopped": "1"]
      case "aria2.tellActive": return []
      case "aria2.tellStopped": return [task("complete")]
      case "aria2.tellStatus":
        store.remove(["abc"])
        return task("complete")
      default: return [:]
      }
    }
    await store.refresh()
    XCTAssertTrue(store.tasks.isEmpty)
    XCTAssertTrue(DownloadHistoryStore(supportDirectory: directory).load().isEmpty)
  }

  func testImportedCompletionDoesNotInventDate() async {
    _ = installTask("complete")
    let store = TaskSnapshotStore(config: config, client: client)
    await store.refresh()
    XCTAssertNil(store.tasks.first?.completionDate)
    await store.refresh()
    XCTAssertNil(store.tasks.first?.completionDate)
  }

  func testTorrentFileListAndPiecesAreDeferredUntilDetails() async throws {
    let requests = RPCMock.install { method, params in
      let summary: [String: Any] = ["gid": "torrent", "status": "active", "totalLength": "100", "bittorrent": ["info": ["name": "Large Torrent"]]]
      switch method {
      case "aria2.getGlobalStat": return ["numActive": "1"]
      case "aria2.tellActive": return [summary]
      case "aria2.getOption": return [:]
      case "aria2.tellStatus":
        XCTAssertTrue((params[1] as? [String] ?? []).contains("bitfield"))
        return summary.merging(["files": [["path": "/tmp/torrent/file"]], "bitfield": "ff"]) { _, new in new }
      default: throw RPCMockFailure(message: "Unexpected \(method)")
      }
    }
    let store = TaskSnapshotStore(config: config, client: client)
    await store.refresh()
    XCTAssertEqual(store.tasks.first?.name, "Large Torrent")
    XCTAssertTrue(store.tasks.first?.files.isEmpty ?? false)
    XCTAssertFalse(requests().contains("aria2.tellStatus"))
    let detail = try await client.getTask("torrent")
    XCTAssertEqual(detail.bitfield, "ff")
    XCTAssertEqual(detail.fileDetails.count, 1)
  }

  func testCorruptHistoryIsPreservedAndReportsError() async throws {
    let file = directory.appendingPathComponent("download-history.json")
    let original = Data("not valid JSON".utf8)
    try original.write(to: file)
    _ = installTask("complete")
    let store = TaskSnapshotStore(config: config, client: client)
    await store.refresh()
    XCTAssertNotNil(store.errorText)
    XCTAssertEqual(try Data(contentsOf: file), original)
  }

  func testSavedRPCSettingsDoNotDisconnectAndPendingSurvivesSaveAndReset() {
    let model = MainWindowModel(config: config, client: client)
    model.settings.rpcPort = 16801
    model.settings.rpcSecret = "changed"
    model.saveSettings()
    XCTAssertEqual(client.endpoint?.port, 16800)
    XCTAssertEqual(client.runningConfig.rpcSecret, "")
    XCTAssertTrue(model.settingsNeedsEngineRestart)
    model.settings.pause.toggle()
    model.saveSettings()
    XCTAssertTrue(model.settingsNeedsEngineRestart)
    model.resetSettings()
    XCTAssertTrue(model.settingsNeedsEngineRestart)
    model.settings.rpcPort = 16800
    model.settings.rpcSecret = ""
    model.saveSettings()
    XCTAssertFalse(model.settingsNeedsEngineRestart)
  }

  func testExternalEngineCannotBeReportedAsRestarted() async {
    let requests = RPCMock.install { _, _ in ["numActive": "0"] }
    let engine = Aria2Engine(config: config)
    let succeeded = await engine.restart(client: client, config: config.updating(system: ["rpc-listen-port": 16801], user: [:]))
    XCTAssertFalse(succeeded)
    XCTAssertEqual(client.endpoint?.port, 16800)
    XCTAssertEqual(requests(), ["aria2.getGlobalStat"])
  }

  func testSaveDuringRestartCannotApplyUnsentSettings() async {
    var finish: CheckedContinuation<Bool, Never>?
    let model = MainWindowModel(config: config, client: client, restartEngine: {
      await withCheckedContinuation { finish = $0 }
    })
    model.settings.rpcPort = 16801
    model.saveSettings()
    model.restartEngine()
    while finish == nil { await Task.yield() }
    model.settings.rpcPort = 16802
    model.saveSettings()
    XCTAssertEqual(model.config.rpcPort, 16801)
    finish?.resume(returning: true)
    while model.isRestartingEngine { await Task.yield() }
    XCTAssertFalse(model.settingsNeedsEngineRestart)
    model.saveSettings()
    XCTAssertTrue(model.settingsNeedsEngineRestart)
    XCTAssertEqual(model.config.rpcPort, 16802)
  }

  func testCompletedControlFilesAreOnlyCleanedOnTransition() async throws {
    _ = installTask("complete")
    let store = TaskSnapshotStore(config: config, client: client)
    let control = directory.appendingPathComponent("file.zip.aria2")
    try Data().write(to: control)
    await store.refresh()
    XCTAssertFalse(FileManager.default.fileExists(atPath: control.path))
    try Data().write(to: control)
    await store.refresh()
    XCTAssertTrue(FileManager.default.fileExists(atPath: control.path), "Unchanged completed tasks must not be scanned again")
  }
}
