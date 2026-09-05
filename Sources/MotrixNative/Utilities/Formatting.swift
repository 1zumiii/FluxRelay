import Foundation

enum Formatting {
  static func speed(_ bytesPerSecond: Int64) -> String {
    "\(bytes(bytesPerSecond))/s"
  }

  static func bytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var index = 0

    while value >= 1024, index < units.count - 1 {
      value /= 1024
      index += 1
    }

    if index == 0 {
      return "\(Int(value)) \(units[index])"
    }

    return String(format: "%.1f %@", value, units[index])
  }

  static func date(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}
