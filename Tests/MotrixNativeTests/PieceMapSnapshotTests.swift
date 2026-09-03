import XCTest
@testable import MotrixNative

final class PieceMapSnapshotTests: XCTestCase {
  func testHexOrderAndPartialLastNibble() throws {
    let result = try PieceMapSnapshot.build(numPieces: 7, bitfield: "aF")
    XCTAssertEqual(result.samples, [1, 0, 1, 0, 1, 1, 1])
    XCTAssertEqual(result.completedPieceCount, 5)
    XCTAssertEqual(try PieceMapSnapshot.build(numPieces: 1, bitfield: "f").samples, [1])
  }

  func testEmptyMalformedAndShortBitfields() throws {
    XCTAssertTrue(try PieceMapSnapshot.build(numPieces: 10, bitfield: "").samples.isEmpty)
    XCTAssertTrue(try PieceMapSnapshot.build(numPieces: 0, bitfield: "f").samples.isEmpty)
    XCTAssertTrue(try PieceMapSnapshot.build(numPieces: -1, bitfield: "f").samples.isEmpty)
    XCTAssertTrue(try PieceMapSnapshot.build(numPieces: 16, bitfield: "f?0f").samples.isEmpty)
    XCTAssertTrue(try PieceMapSnapshot.build(numPieces: 16, bitfield: "f你").samples.isEmpty)
    XCTAssertEqual(try PieceMapSnapshot.build(numPieces: 8, bitfield: "a").samples, [1, 0, 1, 0, 0, 0, 0, 0])
    XCTAssertEqual(try PieceMapSnapshot.build(numPieces: 4, bitfield: "fignored").samples, [1, 1, 1, 1])
  }

  func testMatchesOriginalBucketBoundaries() throws {
    for count in [1, 3, 7, 479, 480, 481, 511, 959, 960, 961, 12345] {
      let bitfield = String(repeating: "a93f07C1", count: (count + 31) / 32)
      let old = referenceSnapshot(numPieces: count, bitfield: bitfield)
      let current = try PieceMapSnapshot.build(numPieces: count, bitfield: bitfield)
      XCTAssertEqual(current.samples, old.samples, "Piece count: \(count)")
      XCTAssertEqual(current.completedPieceCount, old.completed)
      XCTAssertLessThanOrEqual(current.samples.count, 480)
      XCTAssertGreaterThanOrEqual(current.columnCount * current.rowCount, current.samples.count)
    }
  }

  func testLargeMapUsesBoundedOutputAndAccurateCounts() throws {
    let count = 4_000_003
    let result = try PieceMapSnapshot.build(numPieces: count, bitfield: String(repeating: "f", count: (count + 3) / 4))
    XCTAssertEqual(result.samples.count, 480)
    XCTAssertEqual(result.completedPieceCount, count)
    XCTAssertTrue(result.samples.allSatisfy { $0 == 1 })
    let sparse = try PieceMapSnapshot.build(numPieces: Int.max, bitfield: "8")
    XCTAssertEqual(sparse.samples.count, 480)
    XCTAssertEqual(sparse.completedPieceCount, 1)
  }

  func testProcessorInvalidation() async throws {
    let processor = PieceMapProcessor()
    let input = PieceMapInput(taskID: "a", numPieces: 8, bitfield: "80")
    let first = try await processor.snapshot(for: input)
    let cached = try await processor.snapshot(for: input)
    XCTAssertEqual(first, cached)
    XCTAssertTrue(first.samples.withUnsafeBufferPointer { original in
      cached.samples.withUnsafeBufferPointer { original.baseAddress == $0.baseAddress }
    }, "An unchanged map should reuse its sampled storage")
    let updated = try await processor.snapshot(for: .init(taskID: "a", numPieces: 8, bitfield: "ff"))
    XCTAssertEqual(updated.completedPieceCount, 8)
    let resized = try await processor.snapshot(for: .init(taskID: "a", numPieces: 1, bitfield: "ff"))
    XCTAssertEqual(resized.samples, [1])
    let switched = try await processor.snapshot(for: .init(taskID: "b", numPieces: 8, bitfield: "00"))
    XCTAssertEqual(switched.completedPieceCount, 0)
  }

  func testCancelledProcessingDoesNotReplaceCachedMap() async throws {
    let processor = PieceMapProcessor()
    let original = PieceMapInput(taskID: "a", numPieces: 4, bitfield: "a")
    let first = try await processor.snapshot(for: original)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await processor.snapshot(for: .init(taskID: "b", numPieces: 4, bitfield: "f"))
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled maps must not be published")
    } catch is CancellationError {}
    let restored = try await processor.snapshot(for: original)
    XCTAssertEqual(first, restored)
  }

  func testPreparationBenchmark() throws {
    guard ProcessInfo.processInfo.environment["MOTRIX_PERFORMANCE_CHECK"] == "1" else {
      throw XCTSkip("Opt in to the legacy/new comparison with MOTRIX_PERFORMANCE_CHECK=1")
    }
    let count = 16384
    let bitfield = String(repeating: "fa50", count: count / 16)
    let clock = ContinuousClock()
    var oldChecksum = 0
    let oldDuration = clock.measure {
      // The original renderer evaluated columnCount twice for each of 480 cells.
      for _ in 0..<(480 * 2) {
        oldChecksum += referenceSnapshot(numPieces: count, bitfield: bitfield).samples.count
      }
    }
    var newChecksum = 0
    let newDuration = try clock.measure {
      for _ in 0..<100 {
        newChecksum += try PieceMapSnapshot.build(numPieces: count, bitfield: bitfield).samples.count
      }
    }
    XCTAssertEqual(oldChecksum, 480 * 480 * 2)
    XCTAssertEqual(newChecksum, 480 * 100)
    let oldMS = milliseconds(oldDuration)
    let newMS = milliseconds(newDuration) / 100
    print("Piece map preparation (16384 pieces): legacy repeated layout \(oldMS) ms; new single snapshot \(newMS) ms")
  }

  private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
  }

  private func referenceSnapshot(numPieces: Int, bitfield: String) -> (samples: [Double], completed: Int) {
    var pieces: [Bool] = []
    pieces.reserveCapacity(numPieces)
    for character in bitfield {
      guard let nibble = Int(String(character), radix: 16) else { return ([], 0) }
      for shift in stride(from: 3, through: 0, by: -1) {
        if pieces.count == numPieces { break }
        pieces.append(nibble & (1 << shift) != 0)
      }
      if pieces.count == numPieces { break }
    }
    pieces.append(contentsOf: repeatElement(false, count: max(0, numPieces - pieces.count)))
    let sampleCount = min(480, pieces.count)
    let samples = (0..<sampleCount).map { index in
      let start = index * pieces.count / sampleCount
      let end = max(start + 1, (index + 1) * pieces.count / sampleCount)
      let completed = pieces[start..<end].reduce(0) { $0 + ($1 ? 1 : 0) }
      return Double(completed) / Double(end - start)
    }
    return (samples, pieces.filter { $0 }.count)
  }
}
