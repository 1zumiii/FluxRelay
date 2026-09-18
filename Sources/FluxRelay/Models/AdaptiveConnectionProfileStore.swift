import Foundation

enum AdaptiveConnectionProfileStore {
  static func load(from url: URL) -> [String: Int] {
    guard
      let data = try? Data(contentsOf: url),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }

    return object.reduce(into: [:]) { result, entry in
      if let value = entry.value as? Int {
        result[entry.key] = Aria2Limits.clampConnections(value)
      } else if let value = entry.value as? NSNumber {
        result[entry.key] = Aria2Limits.clampConnections(value.intValue)
      }
    }
  }

  static func save(_ profiles: [String: Int], to url: URL) {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let clampedProfiles = profiles.mapValues(Aria2Limits.clampConnections)
      let data = try JSONSerialization.data(withJSONObject: clampedProfiles, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: url, options: .atomic)
    } catch {
      // Adaptive history is only an optimization; downloads must continue if it cannot be persisted.
    }
  }
}
