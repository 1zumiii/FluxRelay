import XCTest
@testable import MotrixNative

final class TLSConfigurationTests: XCTestCase {
  func testStartupOverridesInsecureLegacyCertificateSetting() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for legacyValue: Any in [false, "false", true, "true"] {
      let config = MotrixConfig(
        supportDirectory: directory,
        rpcPort: 16800,
        rpcSecret: "",
        downloadDirectory: directory,
        sessionPath: directory.appendingPathComponent("session"),
        aria2ConfigPath: directory.appendingPathComponent("aria2.conf"),
        aria2BinaryPath: nil,
        aria2LogPath: directory.appendingPathComponent("engine.log"),
        systemConfig: ["check-certificate": legacyValue],
        userConfig: ["proxy-mode": "disabled"]
      )
      XCTAssertEqual(
        config.aria2StartArguments().filter { $0.hasPrefix("--check-certificate=") },
        ["--check-certificate=true"]
      )
    }
  }
}
