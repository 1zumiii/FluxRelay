import Foundation
import Combine

/// Owns temporary torrent tasks until submission succeeds or the sheet closes.
@MainActor
final class AddTaskSession: ObservableObject {
  @Published private(set) var preparedTorrent: PreparedTorrent?
  @Published private(set) var isPreparing = false
  @Published private(set) var isSubmitting = false

  private var isClosed = false
  private let prepare: (URL, URL) async -> PreparedTorrent?
  private let discard: (PreparedTorrent) async -> Void
  private let addLink: (String, NewDownloadOptions) async -> Bool
  private let start: (PreparedTorrent, Set<String>, Bool) async -> Bool

  init(
    prepare: @escaping (URL, URL) async -> PreparedTorrent?,
    discard: @escaping (PreparedTorrent) async -> Void,
    addLink: @escaping (String, NewDownloadOptions) async -> Bool,
    start: @escaping (PreparedTorrent, Set<String>, Bool) async -> Bool
  ) {
    self.prepare = prepare
    self.discard = discard
    self.addLink = addLink
    self.start = start
  }

  func loadTorrent(_ url: URL, directory: URL) async {
    guard !isClosed, !isPreparing, !isSubmitting else { return }
    isPreparing = true
    defer { isPreparing = false }
    let previous = preparedTorrent
    preparedTorrent = nil
    if let previous { await discard(previous) }
    guard !isClosed else { return }

    let prepared = await prepare(url, directory)
    // RPC creation may finish after cancellation. Keep its GID long enough to
    // remove the temporary task instead of cancelling away the response.
    guard !isClosed else {
      if let prepared { await discard(prepared) }
      return
    }
    preparedTorrent = prepared
  }

  @discardableResult
  func submit(uri: String, options: NewDownloadOptions, selectedFileIDs: Set<String>) async -> Bool {
    guard !isClosed, !isPreparing, !isSubmitting else { return false }
    if preparedTorrent != nil, selectedFileIDs.isEmpty { return false }
    isSubmitting = true
    defer { isSubmitting = false }

    let success: Bool
    if let preparedTorrent {
      success = await start(preparedTorrent, selectedFileIDs, options.pauseAtStart)
    } else {
      success = await addLink(uri, options)
    }

    if success {
      // A submitted task belongs to the user, even if the window closed while
      // the RPC was in flight. Never discard it from onDisappear.
      preparedTorrent = nil
      isClosed = true
    } else if isClosed {
      await discardCurrentTorrent()
    }
    return success
  }

  func close() async {
    isClosed = true
    // Submission owns the task until its outcome is known.
    guard !isSubmitting else { return }
    await discardCurrentTorrent()
  }

  private func discardCurrentTorrent() async {
    let prepared = preparedTorrent
    preparedTorrent = nil
    if let prepared { await discard(prepared) }
  }
}
