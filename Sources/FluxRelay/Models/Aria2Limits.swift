enum Aria2Limits {
  static let maximumConnectionsPerServer = 64
  static let connectionRange = 1...maximumConnectionsPerServer

  static func clampConnections(_ value: Int) -> Int {
    min(maximumConnectionsPerServer, max(connectionRange.lowerBound, value))
  }
}
