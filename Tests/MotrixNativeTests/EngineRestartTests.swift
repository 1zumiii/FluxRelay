import Darwin
import Foundation
import XCTest
@testable import MotrixNative

@MainActor
final class EngineRestartTests: XCTestCase {
  func testOwnedEngineRestartChangesEndpointAndPreservesPausedTask() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let binary = root.appendingPathComponent("Resources/engine/aria2c")
    guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("Bundled aria2 is unavailable") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let conf = directory.appendingPathComponent("aria2.conf")
    try "enable-dht=false\nenable-dht6=false\nbt-enable-lpd=false\ndisable-ipv6=true\n".write(to: conf, atomically: true, encoding: .utf8)
    let port = try freePort()
    var nextPort = try freePort()
    while nextPort == port { nextPort = try freePort() }
    let config = MotrixConfig(supportDirectory: directory, rpcPort: port, rpcSecret: "before",
      downloadDirectory: directory, sessionPath: directory.appendingPathComponent("download.session"),
      aria2ConfigPath: conf, aria2BinaryPath: binary, aria2LogPath: directory.appendingPathComponent("aria2.log"),
      systemConfig: ["rpc-listen-port": port, "rpc-secret": "before"], userConfig: ["proxy-mode": "off"])
    let client = Aria2RPCClient(config: config)
    let engine = Aria2Engine(config: config)
    defer { engine.stop() }
    await engine.ensureRunning(client: client)
    _ = try await client.getGlobalStat()
    let gid = try await client.addURI("http://127.0.0.1:1/fixture.zip", directory: directory,
      additionalOptions: ["pause": "true", "checksum": "sha-256=" + String(repeating: "0", count: 64)])
    let next = config.updating(system: ["rpc-listen-port": nextPort, "rpc-secret": "after"], user: nil)
    client.updateDefaults(next)
    XCTAssertEqual(client.endpoint?.port, port)
    let restarted = await engine.restart(client: client, config: next)
    XCTAssertTrue(restarted, engine.lastError ?? "Restart failed")
    XCTAssertEqual(client.endpoint?.port, nextPort)
    let tasks = try await client.listTasks()
    XCTAssertTrue(tasks.contains { $0.id == gid && $0.status == "paused" })
    let options = try await client.getOption(gid)
    XCTAssertEqual(options["checksum"], "sha-256=" + String(repeating: "0", count: 64))
    await engine.stopGracefully(client: client)
  }

  private func freePort() throws -> Int {
    let handle = socket(AF_INET, SOCK_STREAM, 0)
    guard handle >= 0 else { throw POSIXError(.EIO) }
    defer { close(handle) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    let result = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        guard Darwin.bind(handle, $0, size) == 0 else { return Int32(-1) }
        return getsockname(handle, $0, &size)
      }
    }
    guard result == 0 else { throw POSIXError(.EADDRINUSE) }
    return Int(UInt16(bigEndian: address.sin_port))
  }
}
