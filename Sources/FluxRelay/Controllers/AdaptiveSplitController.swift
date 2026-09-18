import Foundation

@MainActor
final class AdaptiveSplitController {
  private var config: AppConfig
  private let client: Aria2RPCClient
  private var appliedSplits: [String: Int] = [:]
  private var lastResult: String?

  private(set) var statusText: String

  init(config: AppConfig, client: Aria2RPCClient) {
    self.config = config
    self.client = client
    self.statusText = config.adaptiveSplitsEnabled
      ? L10n.tr("adaptive_split.standby")
      : L10n.tr("adaptive_split.disabled")
  }

  func updateConfig(_ config: AppConfig) {
    self.config = config
    appliedSplits.removeAll()
    lastResult = nil
    statusText = config.adaptiveSplitsEnabled
      ? L10n.tr("adaptive_split.standby")
      : L10n.tr("adaptive_split.disabled")
  }

  func observe(_ tasks: [Aria2Task]) async {
    guard config.adaptiveSplitsEnabled else {
      statusText = L10n.tr("adaptive_split.disabled")
      return
    }

    let retainedIDs = Set(tasks.filter {
      $0.status == "active" || $0.status == "waiting" || $0.status == "paused"
    }.map(\.id))
    appliedSplits = appliedSplits.filter { retainedIDs.contains($0.key) }

    let candidates = tasks.filter {
      ($0.status == "active" || $0.status == "waiting" || $0.status == "paused") &&
        !$0.isBitTorrent &&
        $0.sourceHost != nil &&
        $0.totalLength > 0 &&
        $0.progress < 0.10 &&
        appliedSplits[$0.id] == nil
    }

    guard !candidates.isEmpty else {
      statusText = lastResult ?? L10n.tr("adaptive_split.standby")
      return
    }

    statusText = L10n.format("adaptive_split.optimizing_tasks", String(candidates.count))
    for task in candidates {
      await applyRecommendedSplit(to: task)
    }
  }

  private func applyRecommendedSplit(to task: Aria2Task) async {
    let split = AdaptiveSplitPolicy.recommendedSplit(
      totalLength: task.totalLength,
      limit: config.adaptiveSplitCeiling
    )

    do {
      let options = try await client.getOption(task.id)
      if Int(options["split"] ?? "") != split {
        try await client.changeOption(task.id, options: ["split": "\(split)"])
      }
      appliedSplits[task.id] = split
      lastResult = L10n.format("adaptive_split.result", String(split))
      statusText = lastResult ?? L10n.tr("adaptive_split.standby")
    } catch {
      statusText = L10n.tr("adaptive_split.retrying")
    }
  }
}
