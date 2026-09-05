import Foundation
import XCTest
@testable import MotrixNative

final class AppIdentityTests: XCTestCase {
  func testLocalizedProductNames() throws {
    XCTAssertEqual(AppIdentity.displayName, "FluxRelay")
    XCTAssertEqual(AppIdentity.version, "0.3.0")
    XCTAssertFalse(AppIdentity.version.isEmpty)
    XCTAssertEqual(AppIdentity.versionLabel, "v\(AppIdentity.version)")
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let brandedKeys = [
      "engine_info.title", "preferences.connection.info", "preferences.open_at_login.subtitle",
      "preferences.storage_notice", "removal.keep_files.description", "removal.trash.description",
      "status_menu.open_app", "status_menu.quit", "status_tooltip.completed_tasks",
      "status_tooltip.rpc_disconnected", "status_tooltip.task_progress", "preferences.language.subtitle"
    ]

    for language in ["en", "zh-Hans"] {
      let url = root.appendingPathComponent("Resources/Localization/\(language).lproj/Localizable.strings")
      let data = try Data(contentsOf: url)
      let strings = try XCTUnwrap(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
      )
      for key in brandedKeys {
        let value = try XCTUnwrap(strings[key], "\(language): \(key)")
        XCTAssertTrue(value.contains(AppIdentity.displayName), "\(language): \(key)")
      }
      XCTAssertFalse(strings.values.contains { $0.contains("Motrix Native") })
    }
  }
}
