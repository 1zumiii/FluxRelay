import Foundation

actor PieceMapProcessor {
  private var cachedInput: PieceMapInput?
  private var cachedSnapshot: PieceMapSnapshot?

  func snapshot(for input: PieceMapInput) throws -> PieceMapSnapshot {
    try Task.checkCancellation()
    if input == cachedInput, let cachedSnapshot { return cachedSnapshot }
    let snapshot = try PieceMapSnapshot.build(numPieces: input.numPieces, bitfield: input.bitfield)
    try Task.checkCancellation()
    cachedInput = input
    cachedSnapshot = snapshot
    return snapshot
  }
}
