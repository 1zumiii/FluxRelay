import Foundation

enum AppIdentity {
  static let displayName = "FluxRelay"

  static let version: String = {
    guard
      Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == displayName,
      let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      !value.isEmpty
    else {
      return "0.3.0"
    }
    return value
  }()

  static var versionLabel: String {
    "v\(version)"
  }
}
