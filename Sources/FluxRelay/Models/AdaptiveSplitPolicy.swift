enum AdaptiveSplitPolicy {
  static func initialSplit(limit: Int) -> Int {
    min(8, Aria2Limits.clampConnections(limit))
  }

  static func recommendedSplit(totalLength: Int64, limit: Int) -> Int {
    let mebibyte = Int64(1024 * 1024)
    let gibibyte = Int64(1024 * 1024 * 1024)
    let recommendation: Int

    switch totalLength {
    case ..<(32 * mebibyte):
      recommendation = 1
    case ..<(128 * mebibyte):
      recommendation = 4
    case ..<(512 * mebibyte):
      recommendation = 8
    case ..<(2 * gibibyte):
      recommendation = 16
    case ..<(8 * gibibyte):
      recommendation = 32
    case ..<(32 * gibibyte):
      recommendation = 48
    default:
      recommendation = 64
    }

    return min(recommendation, Aria2Limits.clampConnections(limit))
  }
}
