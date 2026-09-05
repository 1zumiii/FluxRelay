import Foundation
import XCTest
@testable import MotrixNative

final class DownloadHistoryTests: XCTestCase {
  func testChecksumInference() {
    XCTAssertEqual(ChecksumResult.infer(checksum: "sha-256=abc", status: "error", errorCode: "19", errorMessage: "Name resolution failed"), .pending)
    XCTAssertEqual(ChecksumResult.infer(checksum: nil, status: "error", errorCode: "32", errorMessage: ""), .failed)
    XCTAssertEqual(
      ChecksumResult.infer(checksum: nil, status: "complete", errorCode: "0", errorMessage: ""),
      .notConfigured
    )
    XCTAssertEqual(
      ChecksumResult.infer(checksum: "sha-256=abc", status: "complete", errorCode: "0", errorMessage: ""),
      .passed
    )
    XCTAssertEqual(
      ChecksumResult.infer(checksum: "sha-256=abc", status: "error", errorCode: "32", errorMessage: ""),
      .failed
    )
    XCTAssertEqual(
      ChecksumResult.infer(checksum: "sha-256=abc", status: "active", errorCode: "0", errorMessage: ""),
      .pending
    )
  }

  func testHistoryStoreRoundTripPreservesSearchMetadata() throws {
    let supportDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fluxrelay-history-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let filePath = supportDirectory.appendingPathComponent("archive/report.zip").path
    let source = "https://downloads.example.test/archive/report.zip"
    let task = Aria2Task(
      id: "history-gid",
      status: "complete",
      totalLength: 2048,
      completedLength: 2048,
      uploadLength: 0,
      downloadSpeed: 0,
      uploadSpeed: 0,
      connections: 0,
      pieceLength: 1024,
      numPieces: 2,
      bitfield: "c0",
      errorCode: "0",
      errorMessage: "",
      directory: "/tmp/archive",
      bitTorrentName: nil,
      infoHash: "",
      trackers: [],
      files: [[
        "index": "1",
        "path": filePath,
        "length": "2048",
        "completedLength": "2048",
        "selected": "true",
        "uris": [["uri": source]]
      ]],
      isBitTorrent: false,
      checksum: "sha-256=abc",
      checksumResult: .passed
    )
    let completedAt = Date(timeIntervalSince1970: 1_750_000_000)
    var record = DownloadHistoryRecord(task: task)
    record.completedAt = completedAt
    record.sourceURI = source

    let store = DownloadHistoryStore(supportDirectory: supportDirectory)
    try store.save([record.id: record])
    let loaded = try XCTUnwrap(store.load()[record.id])

    XCTAssertEqual(loaded.completedAt, completedAt)
    XCTAssertEqual(loaded.sourceURI, source)
    XCTAssertEqual(loaded.checksum, "sha-256=abc")
    XCTAssertEqual(loaded.checksumResult, .passed)
    XCTAssertEqual(loaded.task().sourceURI, source)
    XCTAssertEqual(loaded.task().primaryFileURL?.path, filePath)
    XCTAssertTrue(loaded.task().historySearchText.contains(source))
    XCTAssertTrue(loaded.task().historySearchText.contains(filePath))
    XCTAssertTrue(loaded.task().historySearchText.contains(loaded.checksumResult.title))
  }

  func testSettingsChangeSummarySeparatesImmediateAndRestartChanges() {
    let previous = SettingsDraft()
    var current = previous
    current.openAtLogin = true
    current.downloadDirectory = "/tmp/downloads"
    current.rpcPort = 16801
    current.proxyMode = .manual

    let summary = current.changeSummary(comparedTo: previous)

    XCTAssertTrue(summary.immediate.contains("preferences.open_at_login.title"))
    XCTAssertTrue(summary.immediate.contains("preferences.download_folder.title"))
    XCTAssertTrue(summary.restart.contains("preferences.rpc_port.title"))
    XCTAssertTrue(summary.restart.contains("preferences.proxy.mode.title"))
  }

  func testResumedHistoryNoLongerLooksCompleted() throws {
    let task = try XCTUnwrap(Aria2Task.from(["gid": "a", "status": "complete"]))
    var record = DownloadHistoryRecord(task: task)
    record.completedAt = Date()
    let resumed = record.updatingMetadata(from: task.updating(status: "active", downloadSpeed: 0, uploadSpeed: 0), sourceURI: nil, checksum: nil)
    XCTAssertFalse(resumed.isTerminal)
    XCTAssertNil(resumed.completedAt)
  }

  func testAllFileLocationsSourcesAndSelectionSurviveRoundTrip() throws {
    let task = try XCTUnwrap(Aria2Task.from([
      "gid": "multi", "status": "complete", "files": [
        ["path": "/tmp/first", "selected": "true", "uris": [["uri": "https://first.test"]]],
        ["path": "/tmp/second", "selected": "false", "uris": [["uri": "https://second.test"]]]
      ]
    ]))
    let restored = DownloadHistoryRecord(task: task).task()
    XCTAssertTrue(restored.historySearchText.contains("/tmp/second"))
    XCTAssertTrue(restored.historySearchText.contains("https://second.test"))
    XCTAssertFalse(restored.fileDetails[1].isSelected)
    XCTAssertEqual(restored.checksumResult, .unknown)
  }
}
