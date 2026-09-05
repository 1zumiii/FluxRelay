import Foundation
import XCTest
@testable import MotrixNative

@MainActor
final class Aria2PaginationTests: XCTestCase {
  func testWaitingTasksArePaginatedIncludingPausedTasks() async throws {
    let waiting = (0..<205).map { Self.task("waiting-\($0)", status: $0.isMultiple(of: 2) ? "paused" : "waiting") }
    let requests = RPCMock.install { method, params in
      switch method {
      case "aria2.tellActive": return []
      case "aria2.tellWaiting":
        return Self.page(waiting, offset: params[0], limit: params[1])
      case "aria2.tellStopped": return []
      default: XCTFail("unexpected method \(method)"); return []
      }
    }
    let client = makeClient()

    let result = try await client.listTasks(stat: Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 205, stopped: 0))
    XCTAssertEqual(result.map(\.id), waiting.compactMap { $0["gid"] as? String })
    XCTAssertEqual(requests(), ["aria2.tellActive", "aria2.tellWaiting", "aria2.tellWaiting", "aria2.tellWaiting"])
  }

  func testStoppedTasksUseNewestFirstNegativeOffsets() async throws {
    let stopped = (0..<205).map { Self.task("stopped-\($0)", status: "complete") }
    let requests = RPCMock.install { method, params in
      switch method {
      case "aria2.tellActive": return []
      case "aria2.tellWaiting": return []
      case "aria2.tellStopped":
        // aria2's negative offsets address history from the newest item.
        let newestFirst = stopped.reversed()
        return Self.page(Array(newestFirst), offset: params[0], limit: params[1])
      default: XCTFail("unexpected method \(method)"); return []
      }
    }
    let client = makeClient()

    let result = try await client.listTasks(stat: Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 0, stopped: 205))
    XCTAssertEqual(result.map(\.id), stopped.reversed().compactMap { $0["gid"] as? String })
    XCTAssertEqual(requests(), ["aria2.tellActive", "aria2.tellStopped", "aria2.tellStopped", "aria2.tellStopped"])
  }

  func testDuplicateGIDKeepsActiveThenWaitingThenStopped() async throws {
    let requests = RPCMock.install { method, _ in
      switch method {
      case "aria2.tellActive": return [Self.task("same", status: "active")]
      case "aria2.tellWaiting": return [Self.task("same", status: "waiting"), Self.task("waiting", status: "waiting")]
      case "aria2.tellStopped": return [Self.task("same", status: "complete"), Self.task("stopped", status: "complete")]
      default: XCTFail("unexpected method \(method)"); return []
      }
    }
    let client = makeClient()

    let result = try await client.listTasks(stat: Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 1, waiting: 2, stopped: 2))
    XCTAssertEqual(result.map(\.id), ["same", "waiting", "stopped"])
    XCTAssertEqual(result.first?.status, "active")
    XCTAssertEqual(requests().filter { $0 == "aria2.tellWaiting" }.count, 1)
  }

  func testFailureOnLaterPagePropagates() async {
    _ = RPCMock.install { method, params in
      switch method {
      case "aria2.tellActive": return []
      case "aria2.tellWaiting":
        if (params[0] as? Int) == 0 { return (0..<100).map { Self.task("waiting-\($0)", status: "waiting") } }
        throw RPCMockFailure(message: "later page failed")
      case "aria2.tellStopped": return []
      default: XCTFail("unexpected method \(method)"); return []
      }
    }
    let client = makeClient()

    do {
      _ = try await client.listTasks(stat: Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 101, stopped: 0))
      XCTFail("expected later page failure")
    } catch let error as Aria2RPCError {
      guard case .rpc(let message) = error else { return XCTFail("unexpected error \(error)") }
      XCTAssertEqual(message, "later page failed")
    } catch {
      XCTFail("unexpected error \(error)")
    }
  }

  private func makeClient() -> Aria2RPCClient {
    let directory = FileManager.default.temporaryDirectory
    let config = MotrixConfig(
      supportDirectory: directory, rpcPort: 16800, rpcSecret: "", downloadDirectory: directory,
      sessionPath: directory.appendingPathComponent("session"), aria2ConfigPath: directory.appendingPathComponent("aria2.conf"),
      aria2BinaryPath: nil, aria2LogPath: directory.appendingPathComponent("aria2.log"), systemConfig: [:], userConfig: [:]
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RPCMock.self]
    return Aria2RPCClient(config: config, session: URLSession(configuration: configuration))
  }

  private static func task(_ id: String, status: String) -> [String: Any] {
    ["gid": id, "status": status, "totalLength": "1", "completedLength": "0", "files": []]
  }

  private static func page(_ values: [[String: Any]], offset: Any, limit: Any) -> [[String: Any]] {
    let start = offset as? Int ?? 0
    let count = limit as? Int ?? 100
    let index = start >= 0 ? start : max(0, -start - 1)
    guard index < values.count else { return [] }
    return Array(values[index..<min(values.count, index + count)])
  }
}

// The mock has no mutable instance state and confines all responses to MainActor.
// URLProtocol itself declares Sendable unavailable; transfer only this test handle.
private struct RPCMockTransfer: @unchecked Sendable {
  let instance: RPCMock
}

final class RPCMock: URLProtocol {
  typealias Handler = @MainActor (String, [Any]) async throws -> Any
  @MainActor static var handler: Handler!
  @MainActor static var methods: [String] = []

  @MainActor
  static func install(_ handler: @escaping Handler) -> () -> [String] {
    self.handler = handler
    methods = []
    return { self.methods }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let transfer = RPCMockTransfer(instance: self)
    Task { @MainActor in await transfer.instance.respond() }
  }

  @MainActor
  private func respond() async {
    do {
      let bodyData: Data
      if let data = request.httpBody {
        bodyData = data
      } else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let count = stream.read(&buffer, maxLength: buffer.count)
          if count <= 0 { break }
          data.append(buffer, count: count)
        }
        bodyData = data
      } else {
        bodyData = Data()
      }
      let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
      let method = body["method"] as! String
      let params = body["params"] as? [Any] ?? []
      let identifier = body["id"]!
        do {
          Self.methods.append(method)
          let result = try await Self.handler(method, params)
          let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": identifier, "result": result])
          self.finish(data: data)
        } catch let error as RPCMockFailure {
          let data = try! JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": identifier,
            "error": ["code": -1, "message": error.message]
          ])
          self.finish(data: data)
        } catch {
          self.client?.urlProtocol(self, didFailWithError: error)
        }
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  @MainActor
  private func finish(data: Data) {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

struct RPCMockFailure: Error {
  let message: String
}
