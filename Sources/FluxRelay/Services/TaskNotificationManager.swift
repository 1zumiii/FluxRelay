import UserNotifications

@MainActor
enum TaskNotificationManager {
  static func requestAuthorization() {
    Task {
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
  }

  static func notifyDownloadCompleted(_ task: Aria2Task) {
    let content = UNMutableNotificationContent()
    content.title = L10n.tr("notification.download_complete.title")
    content.body = task.isSeeding
      ? L10n.format("notification.download_complete.seeding", task.name)
      : task.name
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "fluxrelay-complete-\(task.id)",
      content: content,
      trigger: nil
    )

    Task {
      try? await UNUserNotificationCenter.current().add(request)
    }
  }
}
