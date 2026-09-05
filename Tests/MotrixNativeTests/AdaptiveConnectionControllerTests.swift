import Foundation
import XCTest
@testable import MotrixNative

@MainActor
final class AdaptiveConnectionControllerTests: XCTestCase {
  func testProgressThresholdFinalizesExistingProbe() async throws {
    let fixture = try Fixture()
    AdaptiveRPCURLProtocol.lastChangedConnections = nil
    var time = Date(timeIntervalSince1970: 1_000)
    let client = fixture.client()
    let controller = AdaptiveConnectionController(config: fixture.config, client: client) { time }

    await controller.observe([fixture.task(progress: 0, speed: 0)])
    time.addTimeInterval(1)
    await controller.observe([fixture.task(progress: 0.20, speed: 0)])

    // A finalized probe must not restart on a later stale progress snapshot.
    time.addTimeInterval(10)
    for _ in 0..<4 { await controller.observe([fixture.task(progress: 0.01, speed: 100)]) }
    XCTAssertNil(try? Data(contentsOf: fixture.config.adaptiveProfilePath))
  }

  func testDeadlineFinalizesWithoutSamples() async throws {
    let fixture = try Fixture()
    var time = Date(timeIntervalSince1970: 2_000)
    let client = fixture.client()
    let controller = AdaptiveConnectionController(config: fixture.config, client: client) { time }

    await controller.observe([fixture.task(progress: 0, speed: 0)])
    time.addTimeInterval(91)
    await controller.observe([fixture.task(progress: 0.01, speed: 0)])

    XCTAssertNil(try? Data(contentsOf: fixture.config.adaptiveProfilePath))
  }

  func testPausedProbeIsRetainedAndTerminalTaskIsCleanedUp() async throws {
    let fixture = try Fixture()
    var time = Date(timeIntervalSince1970: 3_000)
    let controller = AdaptiveConnectionController(config: fixture.config, client: fixture.client()) { time }

    await controller.observe([fixture.task(progress: 0, speed: 0)])
    await controller.observe([fixture.task(status: "paused", progress: 0, speed: 0)])
    time.addTimeInterval(91)
    await controller.observe([fixture.task(status: "complete", progress: 1, speed: 0)])
    XCTAssertEqual(controller.statusText, L10n.tr("adaptive.standby"))
  }

  func testMeasuredBestIsRestoredWhenAdjustmentHasNotSettled() async throws {
    let fixture = try Fixture()
    AdaptiveRPCURLProtocol.lastChangedConnections = nil
    var time = Date(timeIntervalSince1970: 4_000)
    let controller = AdaptiveConnectionController(config: fixture.config, client: fixture.client()) { time }

    let initialTask = fixture.task(progress: 0, speed: 100)
    XCTAssertEqual(initialTask.sourceHost, "example.com")
    await controller.observe([initialTask])
    time.addTimeInterval(7)
    for _ in 0..<4 { await controller.observe([fixture.task(progress: 0.01, speed: 100)]) }
    time.addTimeInterval(1)
    await controller.observe([fixture.task(progress: 0.20, speed: 0)])

    let saved = AdaptiveConnectionProfileStore.load(from: fixture.config.adaptiveProfilePath)
    XCTAssertEqual(saved["example.com"], 48)
    XCTAssertEqual(AdaptiveRPCURLProtocol.lastChangedConnections, 48)
  }

  func testPartialSampleBatchRestoresLastFullyMeasuredConnections() async throws {
    let fixture = try Fixture()
    var time = Date(timeIntervalSince1970: 5_000)
    let controller = AdaptiveConnectionController(config: fixture.config, client: fixture.client()) { time }
    await controller.observe([fixture.task(progress: 0, speed: 100)])
    time.addTimeInterval(7)
    for _ in 0..<4 { await controller.observe([fixture.task(progress: 0.01, speed: 100)]) }
    XCTAssertEqual(AdaptiveRPCURLProtocol.lastChangedConnections, 64)
    time.addTimeInterval(7)
    await controller.observe([fixture.task(progress: 0.02, speed: 200)])
    await controller.observe([fixture.task(progress: 0.20, speed: 200)])
    XCTAssertEqual(AdaptiveRPCURLProtocol.lastChangedConnections, 48)
    XCTAssertEqual(AdaptiveConnectionProfileStore.load(from: fixture.config.adaptiveProfilePath)["example.com"], 48)
  }
}

private final class AdaptiveRPCURLProtocol: URLProtocol {
  nonisolated(unsafe) static var lastChangedConnections: Int?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    var requestData = request.httpBody ?? Data()
    if requestData.isEmpty, let stream = request.httpBodyStream {
      stream.open()
      var buffer = [UInt8](repeating: 0, count: 4_096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        requestData.append(contentsOf: buffer.prefix(count))
      }
      stream.close()
    }
    let body = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any]
    let method = body?["method"] as? String
    let result: Any = method == "aria2.getOption"
      ? ["split": "64", "max-connection-per-server": "48"]
      : "OK"
    if method == "aria2.changeOption",
       let params = body?["params"] as? [Any],
       let options = params.last as? [String: Any] {
      Self.lastChangedConnections = Int(options["max-connection-per-server"] as? String ?? "")
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "result": result])
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@MainActor
private final class Fixture {
  let config: MotrixConfig
  private let directory: URL

  init() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    self.directory = directory
    AdaptiveRPCURLProtocol.lastChangedConnections = nil
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    config = MotrixConfig(
      supportDirectory: directory, rpcPort: 16800, rpcSecret: "", downloadDirectory: directory,
      sessionPath: directory.appendingPathComponent("session"), aria2ConfigPath: directory.appendingPathComponent("aria2.conf"),
      aria2BinaryPath: nil, aria2LogPath: directory.appendingPathComponent("aria2.log"),
      systemConfig: ["max-connection-per-server": 64], userConfig: ["adaptive-connections": true]
    )
  }

  func client() -> Aria2RPCClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AdaptiveRPCURLProtocol.self]
    return Aria2RPCClient(config: config, session: URLSession(configuration: configuration))
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  func task(status: String = "active", progress: Double, speed: Int64) -> Aria2Task {
    let files: [[String: Any]] = [[
      "uris": [["uri": "https://example.com/file.bin"] as [String: Any]]
    ]]
    return Aria2Task(id: "gid", status: status, totalLength: 256 * 1024 * 1024,
      completedLength: Int64(progress * Double(256 * 1024 * 1024)), uploadLength: 0,
      downloadSpeed: speed, uploadSpeed: 0, connections: 48, pieceLength: 1, numPieces: 1,
      bitfield: "", errorCode: "0", errorMessage: "", directory: config.downloadDirectory.path,
      bitTorrentName: nil, infoHash: "", trackers: [],
      files: files, isBitTorrent: false)
  }
}
