import XCTest
@testable import MotrixNative

@MainActor
final class RefreshCoalescerTests: XCTestCase {
  func testTimerTicksDoNotQueueBehindSlowRequests() async {
    let coalescer = RefreshCoalescer()
    var passes = 0
    var entered: CheckedContinuation<Void, Never>?
    var release: CheckedContinuation<Void, Never>?
    let first = Task {
      await coalescer.run {
        passes += 1
        entered?.resume()
        await withCheckedContinuation { release = $0 }
      }
    }
    await withCheckedContinuation { entered = $0 }
    for _ in 0..<20 {
      await coalescer.run(queueFollowUp: false) { passes += 1 }
    }
    release?.resume()
    await first.value
    XCTAssertEqual(passes, 1)
  }

  func testOverlappingRequestsRunSeriallyAndCoalesce() async {
    let coalescer = RefreshCoalescer()
    var passes = 0
    var running = 0
    var maximumRunning = 0
    var entered: CheckedContinuation<Void, Never>?
    var release: CheckedContinuation<Void, Never>?
    let action: @MainActor () async -> Void = {
      passes += 1
      running += 1
      maximumRunning = max(maximumRunning, running)
      if passes == 1 {
        entered?.resume()
        await withCheckedContinuation { release = $0 }
      }
      running -= 1
    }
    let first = Task { await coalescer.run(action) }
    await withCheckedContinuation { entered = $0 }
    // These calls suspend waiting on the first pass, leaving at most one follow-up pass.
    var second: Task<Void, Never>?
    var third: Task<Void, Never>?
    await withCheckedContinuation { ready in
      second = Task {
        ready.resume()
        await coalescer.run(action)
      }
    }
    await withCheckedContinuation { ready in
      third = Task {
        ready.resume()
        await coalescer.run(action)
      }
    }
    release?.resume()
    await first.value
    await second?.value
    await third?.value
    XCTAssertEqual(maximumRunning, 1)
    XCTAssertEqual(passes, 2)
    await coalescer.run(action)
    XCTAssertEqual(passes, 3)
  }
}
