import Foundation

enum TrackerList {
  private static let supportedSchemes: Set<String> = ["http", "https", "udp"]

  static func entries(from rawValue: String) -> [String] {
    var seen = Set<String>()
    return rawValue
      .split { $0 == "," || $0 == "\n" || $0 == "\r" }
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  static func supportedEntries(from rawValue: String) -> [String] {
    entries(from: rawValue).filter { entry in
      guard let scheme = URLComponents(string: entry)?.scheme?.lowercased() else {
        return false
      }
      return supportedSchemes.contains(scheme)
    }
  }

  static func unsupportedEntries(from rawValue: String) -> [String] {
    let supported = Set(supportedEntries(from: rawValue))
    return entries(from: rawValue).filter { !supported.contains($0) }
  }

  static func aria2Value(from rawValue: String) -> String {
    supportedEntries(from: rawValue).joined(separator: ",")
  }
}
