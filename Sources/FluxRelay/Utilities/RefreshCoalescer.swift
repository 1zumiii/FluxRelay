import Foundation

@MainActor
final class RefreshCoalescer {
  private var inFlight: Task<Void, Never>?
  private var needsAnotherPass = false

  func run(queueFollowUp: Bool = true, _ action: @escaping @MainActor () async -> Void) async {
    if let inFlight {
      guard queueFollowUp else { return }
      needsAnotherPass = true
      await inFlight.value
      return
    }

    let task = Task { @MainActor in
      repeat {
        needsAnotherPass = false
        await action()
      } while needsAnotherPass
      inFlight = nil
    }
    inFlight = task
    await task.value
  }
}
