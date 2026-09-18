import Foundation

struct Aria2LogStore {
  static let defaultMaximumFileSize = 5 * 1_024 * 1_024
  static let defaultRetainedArchiveCount = 3

  let activeURL: URL
  let maximumFileSize: Int
  let retainedArchiveCount: Int

  init(
    activeURL: URL,
    maximumFileSize: Int = Self.defaultMaximumFileSize,
    retainedArchiveCount: Int = Self.defaultRetainedArchiveCount
  ) {
    self.activeURL = activeURL
    self.maximumFileSize = maximumFileSize
    self.retainedArchiveCount = max(1, retainedArchiveCount)
  }

  func prepare() {
    compactExistingLog()
    rotateIfNeeded()
  }

  func rotateIfNeeded() {
    let fileManager = FileManager.default
    guard
      let attributes = try? fileManager.attributesOfItem(atPath: activeURL.path),
      let size = attributes[.size] as? NSNumber,
      size.intValue >= maximumFileSize
    else {
      return
    }

    for index in stride(from: retainedArchiveCount, through: 2, by: -1) {
      let source = archiveURL(index: index - 1)
      let destination = archiveURL(index: index)
      try? fileManager.removeItem(at: destination)
      if fileManager.fileExists(atPath: source.path) {
        try? fileManager.moveItem(at: source, to: destination)
      }
    }

    let newestArchive = archiveURL(index: 1)
    try? fileManager.removeItem(at: newestArchive)
    do {
      try fileManager.copyItem(at: activeURL, to: newestArchive)
    } catch {
      try? fileManager.removeItem(at: newestArchive)
      return
    }

    guard let handle = try? FileHandle(forWritingTo: activeURL) else {
      return
    }
    try? handle.truncate(atOffset: 0)
    try? handle.close()
  }

  func archiveURL(index: Int) -> URL {
    let stem = activeURL.deletingPathExtension().lastPathComponent
    return activeURL
      .deletingLastPathComponent()
      .appendingPathComponent("\(stem).\(index).log")
  }

  private func compactExistingLog() {
    guard
      let data = try? Data(contentsOf: activeURL),
      !data.isEmpty,
      let original = String(data: data, encoding: .utf8)
    else {
      return
    }

    let ansiPattern = "\u{001B}\\[[0-9;]*m"
    let plain = original.replacingOccurrences(
      of: ansiPattern,
      with: "",
      options: .regularExpression
    )
    let normalizedNewlines = plain
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    var lines: [String] = []
    var previousLineWasBlank = true
    for line in normalizedNewlines.split(separator: "\n", omittingEmptySubsequences: false) {
      let value = String(line)
      let isBlank = value.trimmingCharacters(in: .whitespaces).isEmpty
      if isBlank {
        if !previousLineWasBlank {
          lines.append("")
        }
      } else {
        lines.append(value)
      }
      previousLineWasBlank = isBlank
    }

    while lines.last?.isEmpty == true {
      lines.removeLast()
    }

    let compacted = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    guard compacted != original else {
      return
    }

    try? Data(compacted.utf8).write(to: activeURL, options: .atomic)
  }
}
