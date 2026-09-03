import Foundation

struct PieceMapInput: Equatable, Sendable {
  let taskID: String
  let numPieces: Int
  let bitfield: String
}

struct PieceMapSnapshot: Equatable, Sendable {
  static let maximumSamples = 480

  let numPieces: Int
  let completedPieceCount: Int
  let samples: [Double]

  var columnCount: Int {
    guard !samples.isEmpty else { return 1 }
    let preferred = Int(ceil(sqrt(Double(samples.count) * 4)))
    return min(samples.count, min(48, max(16, preferred)))
  }

  var rowCount: Int {
    (samples.count + columnCount - 1) / columnCount
  }

  static func unavailable(numPieces: Int) -> Self {
    Self(numPieces: max(0, numPieces), completedPieceCount: 0, samples: [])
  }

  static func build(numPieces: Int, bitfield: String) throws -> Self {
    guard numPieces > 0, !bitfield.isEmpty else { return unavailable(numPieces: numPieces) }
    let sampleCount = min(maximumSamples, numPieces)
    let quotient = numPieces / sampleCount
    let remainder = numPieces % sampleCount
    // Equivalent to index * numPieces / sampleCount without overflowing for large counts.
    func boundary(_ index: Int) -> Int {
      index * quotient + index * remainder / sampleCount
    }

    var completed = [Int](repeating: 0, count: sampleCount)
    var totalCompleted = 0
    var piece = 0
    var sample = 0
    var end = boundary(1)
    for byte in bitfield.utf8 {
      if piece >= numPieces { break }
      if piece.isMultiple(of: 16384) { try Task.checkCancellation() }
      let nibble: UInt8
      switch byte {
      case 48...57: nibble = byte - 48
      case 65...70: nibble = byte - 55
      case 97...102: nibble = byte - 87
      default: return unavailable(numPieces: numPieces)
      }
      for shift in stride(from: 3, through: 0, by: -1) {
        if piece >= numPieces { break }
        if piece == end {
          sample += 1
          end = boundary(sample + 1)
        }
        if nibble & (1 << shift) != 0 {
          completed[sample] += 1
          totalCompleted += 1
        }
        piece += 1
      }
    }

    let samples = (0..<sampleCount).map { index in
      Double(completed[index]) / Double(boundary(index + 1) - boundary(index))
    }
    return Self(numPieces: numPieces, completedPieceCount: totalCompleted, samples: samples)
  }
}
