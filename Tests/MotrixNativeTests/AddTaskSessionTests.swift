import Foundation
import XCTest
@testable import MotrixNative

@MainActor
final class AddTaskSessionTests: XCTestCase {
  func testCancelWhilePreparationPendingDiscardsLateResultOnce() async {
    var entered = false
    var release: CheckedContinuation<Void, Never>?
    var discarded = 0
    let prepared = preparedTorrent("late")
    let session = AddTaskSession(
      prepare: { _, _ in
        entered = true
        await withCheckedContinuation { release = $0 }
        return prepared
      }, discard: { _ in discarded += 1 }, addLink: { _, _ in true }, start: { _, _, _ in true }
    )

    let loading = Task { await session.loadTorrent(URL(fileURLWithPath: "/tmp/a.torrent"), directory: URL(fileURLWithPath: "/tmp")) }
    while !entered { await Task.yield() }
    await session.close()
    release?.resume()
    await loading.value

    XCTAssertEqual(discarded, 1)
    XCTAssertNil(session.preparedTorrent)
  }

  func testDuplicateSubmitWhilePendingCallsAddLinkOnce() async {
    var entered = false
    var release: CheckedContinuation<Bool, Never>?
    var calls = 0
    let session = AddTaskSession(
      prepare: { _, _ in nil }, discard: { _ in },
      addLink: { _, _ in
        calls += 1
        entered = true
        return await withCheckedContinuation { release = $0 }
      }, start: { _, _, _ in true }
    )
    let options = NewDownloadOptions(directory: URL(fileURLWithPath: "/tmp"))
    let first = Task { await session.submit(uri: "https://example.com/a", options: options, selectedFileIDs: []) }
    while !entered { await Task.yield() }
    let duplicate = await session.submit(uri: "https://example.com/a", options: options, selectedFileIDs: [])
    XCTAssertFalse(duplicate)
    release?.resume(returning: true)
    let firstResult = await first.value
    XCTAssertTrue(firstResult)
    XCTAssertEqual(calls, 1)
  }

  func testCloseWhileTorrentSubmissionSucceedsDoesNotDiscardCommittedTask() async {
    let prepared = preparedTorrent("success")
    var entered = false
    var release: CheckedContinuation<Bool, Never>?
    var discarded = 0
    let session = AddTaskSession(
      prepare: { _, _ in prepared }, discard: { _ in discarded += 1 }, addLink: { _, _ in true },
      start: { _, _, _ in
        entered = true
        return await withCheckedContinuation { release = $0 }
      }
    )
    await session.loadTorrent(URL(fileURLWithPath: "/tmp/a.torrent"), directory: URL(fileURLWithPath: "/tmp"))
    let submitting = Task {
      await session.submit(uri: "", options: NewDownloadOptions(directory: URL(fileURLWithPath: "/tmp")), selectedFileIDs: ["1"])
    }
    while !entered { await Task.yield() }
    await session.close()
    release?.resume(returning: true)
    let result = await submitting.value
    XCTAssertTrue(result)
    XCTAssertEqual(discarded, 0)
  }

  func testCloseWhileTorrentSubmissionFailsDiscardsOnce() async {
    let prepared = preparedTorrent("failure")
    var entered = false
    var release: CheckedContinuation<Bool, Never>?
    var discarded = 0
    let session = AddTaskSession(
      prepare: { _, _ in prepared }, discard: { _ in discarded += 1 }, addLink: { _, _ in true },
      start: { _, _, _ in
        entered = true
        return await withCheckedContinuation { release = $0 }
      }
    )
    await session.loadTorrent(URL(fileURLWithPath: "/tmp/a.torrent"), directory: URL(fileURLWithPath: "/tmp"))
    let submitting = Task {
      await session.submit(uri: "", options: NewDownloadOptions(directory: URL(fileURLWithPath: "/tmp")), selectedFileIDs: ["1"])
    }
    while !entered { await Task.yield() }
    await session.close()
    release?.resume(returning: false)
    let result = await submitting.value
    XCTAssertFalse(result)
    XCTAssertEqual(discarded, 1)
  }

  func testReplacementDiscardsPreviousPreparedTask() async {
    var discarded: [String] = []
    let session = AddTaskSession(
      prepare: { url, _ in preparedTorrent(url.lastPathComponent) },
      discard: { discarded.append($0.id) }, addLink: { _, _ in true }, start: { _, _, _ in true }
    )
    await session.loadTorrent(URL(fileURLWithPath: "/tmp/one.torrent"), directory: URL(fileURLWithPath: "/tmp"))
    await session.loadTorrent(URL(fileURLWithPath: "/tmp/two.torrent"), directory: URL(fileURLWithPath: "/tmp"))
    XCTAssertEqual(discarded, ["one.torrent"])
    XCTAssertEqual(session.preparedTorrent?.id, "two.torrent")
  }

  func testEmptySelectedSetDoesNotStartTorrent() async {
    var starts = 0
    let session = AddTaskSession(
      prepare: { _, _ in preparedTorrent("selected") }, discard: { _ in }, addLink: { _, _ in true },
      start: { _, _, _ in starts += 1; return true }
    )
    await session.loadTorrent(URL(fileURLWithPath: "/tmp/a.torrent"), directory: URL(fileURLWithPath: "/tmp"))
    let result = await session.submit(uri: "", options: NewDownloadOptions(directory: URL(fileURLWithPath: "/tmp")), selectedFileIDs: [])
    XCTAssertFalse(result)
    XCTAssertEqual(starts, 0)
  }
}

@MainActor
private func preparedTorrent(_ id: String) -> PreparedTorrent {
  PreparedTorrent(id: id, sourceURL: URL(fileURLWithPath: "/tmp/\(id)"), directory: URL(fileURLWithPath: "/tmp"), files: [])
}
