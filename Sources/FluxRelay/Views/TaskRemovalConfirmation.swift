import AppKit

@MainActor
enum TaskRemovalConfirmation {
  static func confirm(_ task: Aria2Task) -> Bool {
    confirm([task], deletingFiles: false)
  }

  static func confirm(_ tasks: [Aria2Task], deletingFiles: Bool) -> Bool {
    let alert = NSAlert()
    if tasks.count == 1, let task = tasks.first {
      alert.messageText = deletingFiles
        ? L10n.format("removal.single_and_trash.title", task.name)
        : L10n.format("removal.single.title", task.name)
    } else {
      alert.messageText = deletingFiles
        ? L10n.format("removal.multiple_and_trash.title", String(tasks.count))
        : L10n.format("removal.multiple.title", String(tasks.count))
    }
    alert.informativeText = deletingFiles
      ? L10n.tr("removal.trash.description")
      : L10n.tr("removal.keep_files.description")
    alert.alertStyle = .warning
    alert.addButton(withTitle: deletingFiles ? L10n.tr("removal.trash.action") : L10n.tr("action.remove"))
    alert.addButton(withTitle: L10n.tr("action.cancel"))
    alert.buttons.first?.hasDestructiveAction = true
    return alert.runModal() == .alertFirstButtonReturn
  }

  static func confirmClearingCompleted(count: Int) -> Bool {
    let alert = NSAlert()
    alert.messageText = L10n.format("clear_completed.title", String(count))
    alert.informativeText = L10n.tr("clear_completed.description")
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.tr("action.clear"))
    alert.addButton(withTitle: L10n.tr("action.cancel"))
    return alert.runModal() == .alertFirstButtonReturn
  }
}
