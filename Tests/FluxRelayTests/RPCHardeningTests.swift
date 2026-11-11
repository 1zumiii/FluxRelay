import Foundation
import XCTest
@testable import FluxRelay

final class RPCHardeningTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "enable-rpc=true\n".write(to: directory.appendingPathComponent("aria2.conf"), atomically: true, encoding: .utf8)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: directory)
  }

  private func config(secret: String, system: [String: Any] = [:]) -> AppConfig {
    var system = system
    system["rpc-secret"] = secret
    return AppConfig(supportDirectory: directory, rpcPort: 16800, rpcSecret: secret,
      downloadDirectory: directory, sessionPath: directory.appendingPathComponent("session"),
      aria2ConfigPath: directory.appendingPathComponent("aria2.conf"), aria2BinaryPath: nil,
      aria2LogPath: directory.appendingPathComponent("aria2.log"),
      systemConfig: system, userConfig: [:])
  }

  func testTheSecretIsOptional() {
    let arguments = config(secret: "").aria2LaunchArguments()
    XCTAssertFalse(arguments.contains { $0.hasPrefix("--rpc-secret") })
    XCTAssertTrue(arguments.contains("--conf-path=\(directory.appendingPathComponent("aria2.conf").path)"))
  }

  func testTheSecretIsKeptOffTheCommandLine() throws {
    let arguments = config(secret: "hunter2").aria2LaunchArguments()
    XCTAssertFalse(arguments.contains { $0.contains("hunter2") })
    let runtime = directory.appendingPathComponent("aria2.runtime.conf")
    XCTAssertTrue(arguments.contains("--conf-path=\(runtime.path)"))
    XCTAssertTrue(try String(contentsOf: runtime, encoding: .utf8).hasSuffix("rpc-secret=hunter2\n"))
    let permissions = try FileManager.default.attributesOfItem(atPath: runtime.path)[.posixPermissions] as? Int
    XCTAssertEqual(permissions, 0o600)
  }

  func testImportedSettingsCannotOpenTheRPCPort() {
    let arguments = config(secret: "s", system: ["rpc-allow-origin-all": true, "rpc-listen-all": true])
      .aria2StartArguments()
    XCTAssertFalse(arguments.contains { $0.hasPrefix("--rpc-allow-origin-all") })
    XCTAssertEqual(arguments.filter { $0.hasPrefix("--rpc-listen-all") }, ["--rpc-listen-all=false"])
  }

  func testOnlyEngineNotificationsTriggerARefresh() {
    XCTAssertTrue(Aria2EventStream.isNotification(
      .string(#"{"jsonrpc":"2.0","method":"aria2.onDownloadComplete","params":[{"gid":"abc"}]}"#)
    ))
    XCTAssertFalse(Aria2EventStream.isNotification(.string(#"{"jsonrpc":"2.0","id":1,"result":"OK"}"#)))
  }
}
