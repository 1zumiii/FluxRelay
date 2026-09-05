import Foundation

struct Aria2Task: Identifiable {
  let id: String
  let status: String
  let totalLength: Int64
  let completedLength: Int64
  let uploadLength: Int64
  let downloadSpeed: Int64
  let uploadSpeed: Int64
  let connections: Int
  let pieceLength: Int64
  let numPieces: Int
  let bitfield: String
  let errorCode: String
  let errorMessage: String
  let directory: String
  let bitTorrentName: String?
  let infoHash: String
  let trackers: [String]
  let files: [[String: Any]]
  let isBitTorrent: Bool
  let completionDate: Date?
  let checksum: String?
  let checksumResult: ChecksumResult

  init(
    id: String,
    status: String,
    totalLength: Int64,
    completedLength: Int64,
    uploadLength: Int64,
    downloadSpeed: Int64,
    uploadSpeed: Int64,
    connections: Int,
    pieceLength: Int64,
    numPieces: Int,
    bitfield: String,
    errorCode: String,
    errorMessage: String,
    directory: String,
    bitTorrentName: String?,
    infoHash: String,
    trackers: [String],
    files: [[String: Any]],
    isBitTorrent: Bool,
    completionDate: Date? = nil,
    checksum: String? = nil,
    checksumResult: ChecksumResult = .notConfigured
  ) {
    self.id = id
    self.status = status
    self.totalLength = totalLength
    self.completedLength = completedLength
    self.uploadLength = uploadLength
    self.downloadSpeed = downloadSpeed
    self.uploadSpeed = uploadSpeed
    self.connections = connections
    self.pieceLength = pieceLength
    self.numPieces = numPieces
    self.bitfield = bitfield
    self.errorCode = errorCode
    self.errorMessage = errorMessage
    self.directory = directory
    self.bitTorrentName = bitTorrentName
    self.infoHash = infoHash
    self.trackers = trackers
    self.files = files
    self.isBitTorrent = isBitTorrent
    self.completionDate = completionDate
    self.checksum = checksum
    self.checksumResult = checksumResult
  }

  var name: String {
    if let bitTorrentName, !bitTorrentName.isEmpty {
      return bitTorrentName
    }

    for file in files {
      if let path = file["path"] as? String, !path.isEmpty {
        return URL(fileURLWithPath: path).lastPathComponent
      }
      if let uris = file["uris"] as? [[String: Any]] {
        for item in uris {
          if let uri = item["uri"] as? String, !uri.isEmpty {
            return uri
          }
        }
      }
    }
    return id
  }

  var progress: Double {
    guard totalLength > 0 else {
      return 0
    }

    return min(1, max(0, Double(completedLength) / Double(totalLength)))
  }

  var primaryFileURL: URL? {
    for file in files {
      if let path = file["path"] as? String, !path.isEmpty {
        return URL(fileURLWithPath: path)
      }
    }

    return nil
  }

  var sourceHost: String? {
    for file in files {
      guard let uris = file["uris"] as? [[String: Any]] else {
        continue
      }
      for item in uris {
        guard
          let uri = item["uri"] as? String,
          let url = URL(string: uri),
          let scheme = url.scheme?.lowercased(),
          ["http", "https", "ftp", "sftp"].contains(scheme),
          let host = url.host?.lowercased()
        else {
          continue
        }
        return host
      }
    }
    return nil
  }

  var sourceURI: String? {
    for file in files {
      guard let uris = file["uris"] as? [[String: Any]] else {
        continue
      }
      if let uri = uris.first?["uri"] as? String, !uri.isEmpty {
        return uri
      }
    }
    return nil
  }

  var historySearchText: String {
    [
      name,
      sourceURI,
      directory,
      primaryFileURL?.path,
      completionDate.map(Formatting.date),
      checksum,
      checksumResult.title,
      checksumResult.rawValue
    ]
    .compactMap { $0 }
    .joined(separator: " ")
  }

  var fileDetails: [Aria2TaskFile] {
    files.compactMap(Aria2TaskFile.init)
  }

  var isSeeding: Bool {
    isBitTorrent && status == "active" && totalLength > 0 && completedLength >= totalLength
  }

  var isTerminal: Bool {
    status == "complete" || status == "error" || status == "removed"
  }

  var pieceCompletion: [Bool] {
    guard numPieces > 0, !bitfield.isEmpty else { return [] }

    var result: [Bool] = []
    result.reserveCapacity(numPieces)
    for character in bitfield {
      guard let nibble = Int(String(character), radix: 16) else { return [] }
      for shift in stride(from: 3, through: 0, by: -1) {
        result.append((nibble & (1 << shift)) != 0)
        if result.count == numPieces { return result }
      }
    }

    if result.count < numPieces {
      result.append(contentsOf: repeatElement(false, count: numPieces - result.count))
    }
    return result
  }

  var localizedStatus: String {
    if isSeeding {
      return L10n.tr("task.status.seeding")
    }

    switch status {
    case "active": return L10n.tr("task.status.downloading")
    case "waiting": return L10n.tr("task.status.waiting")
    case "paused": return L10n.tr("task.status.paused")
    case "complete": return L10n.tr("task.status.completed")
    case "error": return L10n.tr("task.status.error")
    case "removed": return L10n.tr("task.status.removed")
    default: return status
    }
  }

  func updating(status: String, downloadSpeed: Int64, uploadSpeed: Int64) -> Aria2Task {
    Aria2Task(
      id: id,
      status: status,
      totalLength: totalLength,
      completedLength: completedLength,
      uploadLength: uploadLength,
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
      connections: connections,
      pieceLength: pieceLength,
      numPieces: numPieces,
      bitfield: bitfield,
      errorCode: errorCode,
      errorMessage: errorMessage,
      directory: directory,
      bitTorrentName: bitTorrentName,
      infoHash: infoHash,
      trackers: trackers,
      files: files,
      isBitTorrent: isBitTorrent,
      completionDate: completionDate,
      checksum: checksum,
      checksumResult: checksumResult
    )
  }

  func applyingHistoryMetadata(_ record: DownloadHistoryRecord) -> Aria2Task {
    Aria2Task(
      id: id,
      status: status,
      totalLength: totalLength,
      completedLength: completedLength,
      uploadLength: uploadLength,
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
      connections: connections,
      pieceLength: pieceLength,
      numPieces: numPieces,
      bitfield: bitfield,
      errorCode: errorCode,
      errorMessage: errorMessage,
      directory: directory,
      bitTorrentName: bitTorrentName,
      infoHash: infoHash,
      trackers: trackers,
      files: files,
      isBitTorrent: isBitTorrent,
      completionDate: record.completedAt,
      checksum: record.checksum,
      checksumResult: record.checksumResult
    )
  }

  static func from(_ dictionary: [String: Any]) -> Aria2Task? {
    guard let gid = dictionary["gid"] as? String else {
      return nil
    }

    let bitTorrent = dictionary["bittorrent"] as? [String: Any]
    let bitTorrentInfo = bitTorrent?["info"] as? [String: Any]
    let status = dictionary["status"] as? String ?? "unknown"
    let errorCode = dictionary["errorCode"] as? String ?? "0"
    let errorMessage = dictionary["errorMessage"] as? String ?? ""
    let checksum = dictionary["checksum"] as? String
    let trackers = (bitTorrent?["announceList"] as? [[String]] ?? [])
      .flatMap { $0 }
      .filter { !$0.isEmpty }

    return Aria2Task(
      id: gid,
      status: status,
      totalLength: Int64(dictionary["totalLength"] as? String ?? "0") ?? 0,
      completedLength: Int64(dictionary["completedLength"] as? String ?? "0") ?? 0,
      uploadLength: Int64(dictionary["uploadLength"] as? String ?? "0") ?? 0,
      downloadSpeed: Int64(dictionary["downloadSpeed"] as? String ?? "0") ?? 0,
      uploadSpeed: Int64(dictionary["uploadSpeed"] as? String ?? "0") ?? 0,
      connections: Int(dictionary["connections"] as? String ?? "0") ?? 0,
      pieceLength: Int64(dictionary["pieceLength"] as? String ?? "0") ?? 0,
      numPieces: Int(dictionary["numPieces"] as? String ?? "0") ?? 0,
      bitfield: dictionary["bitfield"] as? String ?? "",
      errorCode: errorCode,
      errorMessage: errorMessage,
      directory: dictionary["dir"] as? String ?? "",
      bitTorrentName: bitTorrentInfo?["name"] as? String,
      infoHash: dictionary["infoHash"] as? String ?? "",
      trackers: Array(Set(trackers)).sorted(),
      files: dictionary["files"] as? [[String: Any]] ?? [],
      isBitTorrent: bitTorrent != nil,
      completionDate: nil,
      checksum: checksum,
      checksumResult: ChecksumResult.infer(
        checksum: checksum,
        status: status,
        errorCode: errorCode,
        errorMessage: errorMessage
      )
    )
  }
}
struct Aria2Peer: Identifiable, Equatable {
  let id: String
  let address: String
  let downloadSpeed: Int64
  let uploadSpeed: Int64
  let isSeeder: Bool
  let isChoking: Bool

  static func from(_ dictionary: [String: Any]) -> Aria2Peer? {
    guard let ip = dictionary["ip"] as? String, !ip.isEmpty else {
      return nil
    }

    let port = dictionary["port"] as? String ?? ""
    let peerID = dictionary["peerId"] as? String ?? ""
    return Aria2Peer(
      id: peerID.isEmpty ? "\(ip):\(port)" : peerID,
      address: port.isEmpty ? ip : "\(ip):\(port)",
      downloadSpeed: Int64(dictionary["downloadSpeed"] as? String ?? "0") ?? 0,
      uploadSpeed: Int64(dictionary["uploadSpeed"] as? String ?? "0") ?? 0,
      isSeeder: dictionary["seeder"] as? String == "true",
      isChoking: dictionary["peerChoking"] as? String == "true"
    )
  }
}

struct Aria2TaskFile: Identifiable, Equatable {
  let id: String
  let path: String
  let length: Int64
  let completedLength: Int64
  let isSelected: Bool

  init?(_ dictionary: [String: Any]) {
    guard let path = dictionary["path"] as? String, !path.isEmpty else {
      return nil
    }

    self.id = dictionary["index"] as? String ?? path
    self.path = path
    self.length = Int64(dictionary["length"] as? String ?? "0") ?? 0
    self.completedLength = Int64(dictionary["completedLength"] as? String ?? "0") ?? 0
    self.isSelected = dictionary["selected"] as? String != "false"
  }

  var name: String {
    URL(fileURLWithPath: path).lastPathComponent
  }

  var progress: Double {
    guard length > 0 else { return 0 }
    return min(1, max(0, Double(completedLength) / Double(length)))
  }
}

struct Aria2GlobalStat: Equatable {
  let downloadSpeed: Int64
  let uploadSpeed: Int64
  let active: Int
  let waiting: Int
  let stopped: Int

  func usingActiveTaskSpeeds(_ tasks: [Aria2Task]) -> Aria2GlobalStat {
    let activeTasks = tasks.filter { $0.status == "active" }
    return Aria2GlobalStat(
      downloadSpeed: activeTasks.reduce(Int64(0)) { $0 + $1.downloadSpeed },
      uploadSpeed: activeTasks.reduce(Int64(0)) { $0 + $1.uploadSpeed },
      active: active,
      waiting: waiting,
      stopped: stopped
    )
  }
}

enum Aria2RPCError: Error {
  case invalidURL
  case invalidResponse
  case rpc(String)
}

@MainActor
final class Aria2RPCClient {
  private var config: MotrixConfig
  private let session: URLSession
  private var requestID = 0

  init(config: MotrixConfig, session: URLSession = .shared) {
    self.config = config
    self.session = session
  }

  var endpoint: URL? {
    URL(string: "http://127.0.0.1:\(config.rpcPort)/jsonrpc")
  }

  func updateConfig(_ config: MotrixConfig) {
    self.config = config
  }

  func getGlobalStat() async throws -> Aria2GlobalStat {
    let result: [String: Any] = try await call("aria2.getGlobalStat")
    return Aria2GlobalStat(
      downloadSpeed: Int64(result["downloadSpeed"] as? String ?? "0") ?? 0,
      uploadSpeed: Int64(result["uploadSpeed"] as? String ?? "0") ?? 0,
      active: Int(result["numActive"] as? String ?? "0") ?? 0,
      waiting: Int(result["numWaiting"] as? String ?? "0") ?? 0,
      stopped: Int(result["numStopped"] as? String ?? "0") ?? 0
    )
  }

  /// Returns a complete task snapshot for the current aria2 queues and history.
  ///
  /// `stat` may be supplied when the caller already fetched a global snapshot.
  /// The counts are used only as a pagination bound; an empty or short page still
  /// terminates pagination so a queue changing while it is being read cannot loop.
  func listTasks(stat: Aria2GlobalStat? = nil) async throws -> [Aria2Task] {
    let snapshot: Aria2GlobalStat
    if let stat {
      snapshot = stat
    } else {
      snapshot = try await getGlobalStat()
    }
    let active: [[String: Any]] = try await call("aria2.tellActive")
    let waiting = try await paginatedTasks(
      method: "aria2.tellWaiting",
      count: snapshot.waiting,
      offset: { page in page * 100 }
    )
    let stopped = try await paginatedTasks(
      method: "aria2.tellStopped",
      count: snapshot.stopped,
      offset: { page in -1 - page * 100 }
    )

    var seen = Set<String>()
    return (active + waiting + stopped).compactMap { dictionary in
      guard let task = Aria2Task.from(dictionary), seen.insert(task.id).inserted else {
        return nil
      }
      return task
    }
  }

  private func paginatedTasks(
    method: String,
    count: Int,
    offset: (Int) -> Int
  ) async throws -> [[String: Any]] {
    guard count > 0 else { return [] }

    let pageSize = 100
    var page = 0
    var result: [[String: Any]] = []
    result.reserveCapacity(count)

    while result.count < count {
      let items: [[String: Any]] = try await call(
        method,
        params: [offset(page), pageSize]
      )
      result.append(contentsOf: items)
      page += 1
      if items.isEmpty || items.count < pageSize { break }
    }
    return result
  }

  func addURI(_ uri: String, directory: URL, additionalOptions: [String: Any] = [:]) async throws -> String {
    var options: [String: Any] = additionalOptions
    options["dir"] = directory.path
    for (key, value) in config.adaptiveTaskOptions(for: uri) {
      options[key] = value
    }
    return try await call("aria2.addUri", params: [[uri], options])
  }

  @discardableResult
  func addTorrent(
    _ fileURL: URL,
    directory: URL,
    additionalOptions: [String: Any] = [:]
  ) async throws -> String {
    let data = try Data(contentsOf: fileURL)
    let encoded = data.base64EncodedString()
    var options: [String: Any] = additionalOptions
    options["dir"] = directory.path
    return try await call("aria2.addTorrent", params: [encoded, [], options])
  }

  func pause(_ gid: String) async throws {
    let _: String = try await call("aria2.pause", params: [gid])
  }

  func unpause(_ gid: String) async throws {
    let _: String = try await call("aria2.unpause", params: [gid])
  }

  func remove(_ gid: String) async throws {
    let _: String = try await call("aria2.remove", params: [gid])
  }

  func removeDownloadResult(_ gid: String) async throws {
    let _: String = try await call("aria2.removeDownloadResult", params: [gid])
  }

  func getOption(_ gid: String) async throws -> [String: String] {
    try await call("aria2.getOption", params: [gid])
  }

  func changeOption(_ gid: String, options: [String: String]) async throws {
    let _: String = try await call("aria2.changeOption", params: [gid, options])
  }

  @discardableResult
  func changePosition(_ gid: String, position: Int, how: String) async throws -> Int {
    try await call("aria2.changePosition", params: [gid, position, how])
  }

  func getFiles(_ gid: String) async throws -> [Aria2TaskFile] {
    let result: [[String: Any]] = try await call("aria2.getFiles", params: [gid])
    return result.compactMap(Aria2TaskFile.init)
  }

  func getPeers(_ gid: String) async throws -> [Aria2Peer] {
    let result: [[String: Any]] = try await call("aria2.getPeers", params: [gid])
    return result.compactMap(Aria2Peer.from)
  }

  func saveSession() async throws {
    let _: String = try await call("aria2.saveSession")
  }

  func shutdown() async throws {
    let _: String = try await call("aria2.shutdown")
  }

  private func call<T>(_ method: String, params: [Any] = []) async throws -> T {
    guard let endpoint else {
      throw Aria2RPCError.invalidURL
    }

    requestID += 1
    var finalParams: [Any] = params
    if !config.rpcSecret.isEmpty {
      finalParams.insert("token:\(config.rpcSecret)", at: 0)
    }

    let payload: [String: Any] = [
      "jsonrpc": "2.0",
      "id": requestID,
      "method": method,
      "params": finalParams
    ]

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

    let (data, response) = try await session.data(for: request)
    guard
      let http = response as? HTTPURLResponse,
      (200..<300).contains(http.statusCode),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw Aria2RPCError.invalidResponse
    }

    if let error = object["error"] as? [String: Any] {
      let message = error["message"] as? String ?? L10n.tr("error.rpc_failed")
      throw Aria2RPCError.rpc(message)
    }

    guard let result = object["result"] as? T else {
      throw Aria2RPCError.invalidResponse
    }

    return result
  }
}
