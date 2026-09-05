import Foundation

enum ChecksumResult: String, Codable, Equatable {
  case notConfigured = "not-configured"
  case pending
  case passed
  case failed
  case unknown

  var localizationKey: String {
    switch self {
    case .notConfigured: return "task_detail.checksum_not_configured"
    case .pending: return "task_detail.checksum_pending"
    case .passed: return "task_detail.checksum_passed"
    case .failed: return "task_detail.checksum_failed"
    case .unknown: return "task_detail.checksum_unknown"
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
    if status == "error", errorCode == "32" { return .failed }
    guard let checksum, !checksum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .notConfigured
    }

    if status == "complete" {
      return .passed
    }

    return .pending
  }
}

struct DownloadHistoryFile: Codable, Equatable {
  let path: String
  let length: Int64
  let completedLength: Int64
  var selected: Bool? = nil
  var uris: [String]? = nil
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
  var checksumKnown: Bool? = nil
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
    result.status = task.status
    result.errorCode = task.errorCode
    result.errorMessage = task.errorMessage
    if !task.isSeeding {
      result.completedAt = nil
    } else if result.completedAt == nil, result.completedLength < task.totalLength {
      result.completedAt = Date()
    }
    result.name = task.name
    if !task.directory.isEmpty { result.directory = task.directory }
    if result.files.isEmpty, !task.fileDetails.isEmpty {
      result.files = task.fileDetails.map {
        DownloadHistoryFile(path: $0.path, length: $0.length, completedLength: $0.completedLength, selected: $0.isSelected)
      }
    }
    result.sourceURI = sourceURI ?? result.sourceURI ?? task.sourceURI
    result.checksum = checksum ?? task.checksum ?? result.checksum
    result.checksumResult = ChecksumResult.infer(checksum: result.checksum, status: task.status, errorCode: task.errorCode, errorMessage: task.errorMessage)
    return result
  }

  init(
    task: Aria2Task,
    existing: DownloadHistoryRecord? = nil,
    sourceURI: String? = nil,
    checksum: String? = nil,
    checksumKnown: Bool? = nil
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
    let taskFiles = task.files.compactMap { file -> DownloadHistoryFile? in
      guard let detail = Aria2TaskFile(file) else { return nil }
      return DownloadHistoryFile(path: detail.path, length: detail.length, completedLength: detail.completedLength,
        selected: detail.isSelected, uris: (file["uris"] as? [[String: Any]])?.compactMap { $0["uri"] as? String })
    }
    files = taskFiles.isEmpty ? (existing?.files ?? []) : taskFiles
    self.sourceURI = sourceURI ?? existing?.sourceURI ?? task.sourceURI
    // aria2 has no completion timestamp. Date() is valid only for an observed
    // transition; importing an already-complete task must not invent its date.
    if task.status == "complete" || task.isSeeding {
      completedAt = existing?.completedAt ?? (existing != nil && existing?.status != "complete" ? Date() : nil)
    } else {
      completedAt = nil
    }
    self.checksum = checksum ?? task.checksum ?? existing?.checksum
    self.checksumKnown = checksumKnown ?? existing?.checksumKnown ?? (self.checksum != nil ? true : nil)
    checksumResult = ChecksumResult.infer(
      checksum: self.checksum,
      status: task.status,
      errorCode: task.errorCode,
      errorMessage: task.errorMessage
    )
    if self.checksum == nil, self.checksumKnown != true, checksumResult != .failed { checksumResult = .unknown }
    isBitTorrent = task.isBitTorrent
    infoHash = task.infoHash
    trackers = task.trackers
    pieceLength = task.pieceLength
    numPieces = task.numPieces
    bitfield = ""
  }

  func task() -> Aria2Task {
    var taskFiles = files.enumerated().map { index, file in
      [
        "index": "\(index + 1)",
        "path": file.path,
        "length": "\(file.length)",
        "completedLength": "\(file.completedLength)",
        "selected": (file.selected ?? true) ? "true" : "false",
        "uris": (file.uris ?? []).map { ["uri": $0] }
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
        for index in taskFiles.indices where (taskFiles[index]["uris"] as? [[String: String]] ?? []).isEmpty {
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
      checksumResult: checksumResult,
      recordedSourceURI: sourceURI
    )
  }
}

struct DownloadHistoryStore {
  let fileURL: URL

  init(supportDirectory: URL) {
    fileURL = supportDirectory.appendingPathComponent("download-history.json")
  }

  func load() -> [String: DownloadHistoryRecord] {
    (try? loadChecked()) ?? [:]
  }

  func loadChecked() throws -> [String: DownloadHistoryRecord] {
    try loadState().records
  }

  func loadState() throws -> (records: [String: DownloadHistoryRecord], removedIDs: Set<String>) {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return ([:], []) }
    let data = try Data(contentsOf: fileURL)
    let payload = try decoder.decode(Payload.self, from: data)
    let records = payload.records.map { saved in
      var record = saved
      record.checksumResult = ChecksumResult.infer(checksum: record.checksum, status: record.status, errorCode: record.errorCode, errorMessage: record.errorMessage)
      if record.checksum == nil, record.checksumKnown != true, record.checksumResult != .failed {
        record.checksumResult = .unknown
      }
      return (record.id, record)
    }
    return (Dictionary(records, uniquingKeysWith: { _, latest in latest }), Set(payload.removedIDs ?? []))
  }

  func save(_ records: [String: DownloadHistoryRecord], removedIDs: Set<String> = []) throws {
    let payload = Payload(records: records.values.sorted {
      switch ($0.completedAt, $1.completedAt) {
      case let (left?, right?):
        if left != right { return left > right }
      case (_?, nil): return true
      case (nil, _?): return false
      default: break
      }
      return $0.id < $1.id
    }, removedIDs: removedIDs.sorted())
    let data = try encoder.encode(payload)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
  }

  private struct Payload: Codable {
    let records: [DownloadHistoryRecord]
    var removedIDs: [String]? = nil
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
