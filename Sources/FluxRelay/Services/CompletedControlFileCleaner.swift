import Foundation

enum CompletedControlFileCleaner {
  static func clean(tasks: [Aria2Task]) {
    let fileManager = FileManager.default

    for task in tasks where task.status == "complete" {
      for controlFile in controlFiles(for: task) {
        var isDirectory: ObjCBool = false
        guard
          fileManager.fileExists(atPath: controlFile.path, isDirectory: &isDirectory),
          !isDirectory.boolValue
        else {
          continue
        }

        try? fileManager.removeItem(at: controlFile)
      }
    }
  }

  static func controlFiles(for task: Aria2Task) -> Set<URL> {
    let fileURLs = task.fileDetails.map { URL(fileURLWithPath: $0.path) }
    var candidates = Set(fileURLs.map {
      URL(fileURLWithPath: $0.path + ".aria2")
    })

    if task.isBitTorrent, let bitTorrentName = task.bitTorrentName, !bitTorrentName.isEmpty {
      let directory = task.directory.isEmpty
        ? task.primaryFileURL?.deletingLastPathComponent()
        : URL(fileURLWithPath: task.directory, isDirectory: true)
      if let directory {
        let root = directory.appendingPathComponent(bitTorrentName)
        candidates.insert(URL(fileURLWithPath: root.path + ".aria2"))
      }
    } else if task.isBitTorrent, fileURLs.count > 1, let commonDirectory = commonDirectory(of: fileURLs) {
      candidates.insert(URL(fileURLWithPath: commonDirectory.path + ".aria2"))
    }

    return candidates
  }

  private static func commonDirectory(of files: [URL]) -> URL? {
    guard var common = files.first?.deletingLastPathComponent().pathComponents else {
      return nil
    }

    for file in files.dropFirst() {
      let components = file.deletingLastPathComponent().pathComponents
      let sharedCount = zip(common, components).prefix { pair in pair.0 == pair.1 }.count
      common = Array(common.prefix(sharedCount))
    }

    guard common.count > 1 else {
      return nil
    }
    return URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
  }
}
