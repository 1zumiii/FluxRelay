import Foundation

enum ChecksumResult: String, Codable, Equatable {
  case notConfigured = "not-configured"
  case pending
  case passed
  case failed

  var localizationKey: String {
    switch self {
    case .notConfigured: return "task_detail.checksum_not_configured"
    case .pending: return "task_detail.checksum_pending"
    case .passed: return "task_detail.checksum_passed"
    case .failed: return "task_detail.checksum_failed"
    }
  }

  var title: String {
    L10n.tr(localizationKey)
  }

  static func infer(
    checksum: String?,
    status: String,
    errorCode: String,
    errorMessage: String
  ) -> ChecksumResult {
    guard let checksum, !checksum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .notConfigured
    }

    if status == "complete" {
      return .passed
    }

    let normalizedError = errorMessage.lowercased()
    if status == "error" && (errorCode == "19" || normalizedError.contains("checksum") || normalizedError.contains("hash")) {
      return .failed
    }

    return .pending
  }
}

struct DownloadHistoryFile: Codable, Equatable {
  let path: String
  let length: Int64
  let completedLength: Int64
}

struct DownloadHistoryRecord: Codable, Equatable, Identifiable {
  let id: String
  var name: String
  var status: String
  var totalLength: Int64
  var completedLength: Int64
  var uploadLength: Int64
  var errorCode: String
  var errorMessage: String
  var directory: String
  var files: [DownloadHistoryFile]
  var sourceURI: String?
  var completedAt: Date?
  var checksum: String?
  var checksumResult: ChecksumResult
  var isBitTorrent: Bool
  var infoHash: String
  var trackers: [String]
  var pieceLength: Int64
  var numPieces: Int
  var bitfield: String

  var isTerminal: Bool {
    status == "complete" || status == "error" || status == "removed"
  }

  func updatingMetadata(from task: Aria2Task, sourceURI: String?, checksum: String?) -> DownloadHistoryRecord {
    var result = self
    result.name = task.name
    if !task.directory.isEmpty { result.directory = task.directory }
    if result.files.isEmpty, !task.fileDetails.isEmpty {
      result.files = task.fileDetails.map {
        DownloadHistoryFile(path: $0.path, length: $0.length, completedLength: $0.completedLength)
      }
    }
    result.sourceURI = sourceURI ?? task.sourceURI ?? result.sourceURI
    result.checksum = checksum ?? task.checksum ?? result.checksum
    return result
  }

  init(
    task: Aria2Task,
    existing: DownloadHistoryRecord? = nil,
    sourceURI: String? = nil,
    checksum: String? = nil
  ) {
    id = task.id
    name = task.name
    status = task.status
    totalLength = task.totalLength
    completedLength = task.completedLength
    uploadLength = task.uploadLength
    errorCode = task.errorCode
    errorMessage = task.errorMessage
    directory = task.directory.isEmpty ? (existing?.directory ?? "") : task.directory
    let taskFiles = task.fileDetails.map {
      DownloadHistoryFile(path: $0.path, length: $0.length, completedLength: $0.completedLength)
    }
    files = taskFiles.isEmpty ? (existing?.files ?? []) : taskFiles
    self.sourceURI = sourceURI ?? task.sourceURI ?? existing?.sourceURI
    completedAt = task.status == "complete" ? (existing?.completedAt ?? Date()) : nil
    self.checksum = checksum ?? task.checksum ?? existing?.checksum
    checksumResult = ChecksumResult.infer(
      checksum: self.checksum,
      status: task.status,
      errorCode: task.errorCode,
      errorMessage: task.errorMessage
    )
    isBitTorrent = task.isBitTorrent
    infoHash = task.infoHash
    trackers = task.trackers
    pieceLength = task.pieceLength
    numPieces = task.numPieces
    bitfield = task.bitfield
  }

  func task() -> Aria2Task {
    var taskFiles = files.enumerated().map { index, file in
      [
        "index": "\(index + 1)",
        "path": file.path,
        "length": "\(file.length)",
        "completedLength": "\(file.completedLength)",
        "selected": "true"
      ] as [String: Any]
    }

    if let sourceURI, !sourceURI.isEmpty {
      if taskFiles.isEmpty {
        let path = directory.isEmpty ? name : URL(fileURLWithPath: directory).appendingPathComponent(name).path
        taskFiles = [[
          "index": "1",
          "path": path,
          "length": "\(totalLength)",
          "completedLength": "\(completedLength)",
          "selected": "true",
          "uris": [["uri": sourceURI]]
        ]]
      } else {
        for index in taskFiles.indices where taskFiles[index]["uris"] == nil {
          taskFiles[index]["uris"] = [["uri": sourceURI]]
        }
      }
    }

    return Aria2Task(
      id: id,
      status: status,
      totalLength: totalLength,
      completedLength: completedLength,
      uploadLength: uploadLength,
      downloadSpeed: 0,
      uploadSpeed: 0,
      connections: 0,
      pieceLength: pieceLength,
      numPieces: numPieces,
      bitfield: bitfield,
      errorCode: errorCode,
      errorMessage: errorMessage,
      directory: directory,
      bitTorrentName: isBitTorrent ? name : nil,
      infoHash: infoHash,
      trackers: trackers,
      files: taskFiles,
      isBitTorrent: isBitTorrent,
      completionDate: completedAt,
      checksum: checksum,
      checksumResult: checksumResult
    )
  }
}

struct DownloadTaskMetadata {
  let sourceURI: String?
  let checksum: String?
}

struct DownloadHistoryStore {
  let fileURL: URL

  init(supportDirectory: URL) {
    fileURL = supportDirectory.appendingPathComponent("download-history.json")
  }

  func load() -> [String: DownloadHistoryRecord] {
    guard
      let data = try? Data(contentsOf: fileURL),
      let payload = try? decoder.decode(Payload.self, from: data)
    else {
      return [:]
    }
    return Dictionary(payload.records.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
  }

  func save(_ records: [String: DownloadHistoryRecord]) throws {
    let payload = Payload(records: records.values.sorted {
      switch ($0.completedAt, $1.completedAt) {
      case let (left?, right?):
        if left != right { return left > right }
      case (_?, nil): return true
      case (nil, _?): return false
      default: break
      }
      return $0.id < $1.id
    })
    let data = try encoder.encode(payload)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
  }

  private struct Payload: Codable {
    let records: [DownloadHistoryRecord]
  }

  private var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
