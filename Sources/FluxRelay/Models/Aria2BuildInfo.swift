import Foundation

struct Aria2BuildInfo: Decodable {
  struct Compatibility: Decodable {
    let maxConnectionsPerServer: Int
  }

  let architecture: String
  let aria2Commit: String
  let aria2Version: String
  let compatibility: Compatibility
  let dependencies: [String: String]
  let minimumMacOS: String
  let tlsBackend: String

  var shortCommit: String {
    String(aria2Commit.prefix(8))
  }

  var dependencySummary: String {
    dependencies
      .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
      .map { "\($0.key) \($0.value)" }
      .joined(separator: ", ")
  }

  static func load(bundle: Bundle = .main) -> Aria2BuildInfo? {
    guard let resourceURL = bundle.resourceURL else {
      return nil
    }

    let url = resourceURL
      .appendingPathComponent("engine", isDirectory: true)
      .appendingPathComponent("aria2-build.json")
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }
    return try? JSONDecoder().decode(Aria2BuildInfo.self, from: data)
  }
}

enum Aria2BinaryInspector {
  static func versionOutput(at binaryURL: URL) -> String? {
    run(executable: binaryURL, arguments: ["--version"])
  }

  static func architectures(at binaryURL: URL) -> String? {
    run(
      executable: URL(fileURLWithPath: "/usr/bin/lipo"),
      arguments: ["-archs", binaryURL.path]
    )?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func acceptsConnectionLimit(at binaryURL: URL, limit: Int) -> Bool {
    run(
      executable: binaryURL,
      arguments: [
        "--max-connection-per-server=\(limit)",
        "--split=\(limit)",
        "--version"
      ]
    ) != nil
  }

  private static func run(executable: URL, arguments: [String]) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        return nil
      }
      return String(
        data: output.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      )
    } catch {
      return nil
    }
  }
}
