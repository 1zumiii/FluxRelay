import SwiftUI

struct TaskCard: View {
  let task: Aria2Task
  @ObservedObject var model: MainWindowModel

  var body: some View {
    HStack(spacing: 0) {
      Button {
        if model.isSelectingTasks {
          model.toggleTaskSelection(task)
        } else {
          model.showDetails(task)
        }
      } label: {
        HStack(spacing: 16) {
          if model.isSelectingTasks {
            Image(systemName: model.selectedTaskIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
              .font(.system(size: 17, weight: .medium))
              .foregroundStyle(model.selectedTaskIDs.contains(task.id) ? .teal : .secondary)
          }

          taskIcon

          VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
              Text(task.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

              StatusPill(status: task.status, isSeeding: task.isSeeding)
            }

            Text(task.primaryFileURL?.deletingLastPathComponent().path ?? task.id)
              .font(.system(size: 12))
              .foregroundStyle(.tertiary)
              .lineLimit(1)

            HStack(spacing: 10) {
              ProgressView(value: task.progress)
                .tint(.teal)
                .frame(maxWidth: 280)

              Text("\(Int((task.progress * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
          }

          Spacer(minLength: 16)

          VStack(alignment: .trailing, spacing: 5) {
            Text(task.downloadSpeed > 0 ? Formatting.speed(task.downloadSpeed) : L10n.tr("task.status.idle"))
              .font(.system(size: 13, weight: .medium, design: .rounded))
              .foregroundStyle(task.downloadSpeed > 0 ? .primary : .secondary)

            Text("\(Formatting.bytes(task.completedLength)) / \(Formatting.bytes(task.totalLength))")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)

            if let completionDate = task.completionDate {
              Text(Formatting.date(completionDate))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
          }
          .frame(width: 170, alignment: .trailing)

          if !model.isSelectingTasks {
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if !model.isSelectingTasks {
        HStack(spacing: 4) {
          if task.status == "active" {
            iconButton("pause.fill", help: L10n.tr("action.pause")) {
              Task { await model.pause(task) }
            }
          } else if task.status == "paused" || task.status == "waiting" {
            iconButton("play.fill", help: L10n.tr("action.resume")) {
              Task { await model.resume(task) }
            }
          }

          iconButton("folder", help: L10n.tr("task.action.reveal")) {
            model.reveal(task)
          }

          iconButton("trash", help: L10n.tr("action.remove")) {
            Task { await model.remove(task) }
          }
        }
        .padding(.trailing, 16)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(model.selectedTaskIDs.contains(task.id) ? Color.teal.opacity(0.09) : Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 3)
    }
    .contextMenu {
      Button(L10n.tr("task.action.view_details")) {
        model.showDetails(task)
      }

      Divider()

      if task.status == "active" {
        Button(L10n.tr("action.pause")) {
          Task { await model.pause(task) }
        }
      } else if task.status == "paused" || task.status == "waiting" {
        Button(L10n.tr("action.resume")) {
          Task { await model.resume(task) }
        }
      }

      Button(L10n.tr("task.action.reveal_file")) {
        model.reveal(task)
      }

      if task.status == "waiting" || task.status == "paused" {
        Menu(L10n.tr("task.queue_priority")) {
          Button(L10n.tr("task.queue.move_top")) { Task { await model.moveInQueue(task, .top) } }
          Button(L10n.tr("task.queue.move_up")) { Task { await model.moveInQueue(task, .up) } }
          Button(L10n.tr("task.queue.move_down")) { Task { await model.moveInQueue(task, .down) } }
          Button(L10n.tr("task.queue.move_bottom")) { Task { await model.moveInQueue(task, .bottom) } }
        }
      }

      Divider()

      Button(L10n.tr("action.remove"), role: .destructive) {
        Task { await model.remove(task) }
      }
      Button(L10n.tr("task.action.remove_and_trash"), role: .destructive) {
        Task { await model.remove(task, deletingFiles: true) }
      }
    }
  }

  private var taskIcon: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(statusColor.opacity(0.16))

      Image(systemName: task.isSeeding ? "arrow.up" : task.status == "complete" ? "checkmark" : "arrow.down")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(statusColor)
    }
    .frame(width: 46, height: 46)
  }

  private var statusColor: Color {
    if task.isSeeding { return .indigo }
    switch task.status {
    case "active": return .teal
    case "paused": return .orange
    case "complete": return .green
    case "error": return .red
    default: return .secondary
    }
  }

  private func iconButton(_ image: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      ZStack {
        Circle()
          .fill(Color.primary.opacity(0.055))

        Image(systemName: image)
          .foregroundStyle(.secondary)
      }
      .frame(width: 30, height: 30)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

struct TaskSelectionBar: View {
  @ObservedObject var model: MainWindowModel

  var body: some View {
    HStack(spacing: 10) {
      Text(L10n.format("task.selection.count", String(model.selectedTaskIDs.count)))
        .font(.system(size: 13, weight: .semibold))

      Button(model.selectedTaskIDs.count == model.filteredTasks.count ? L10n.tr("action.deselect_all") : L10n.tr("action.select_all")) {
        if model.selectedTaskIDs.count == model.filteredTasks.count {
          model.selectedTaskIDs.removeAll()
        } else {
          model.selectAllVisibleTasks()
        }
      }
      .buttonStyle(.link)

      Spacer()

      Button {
        Task { await model.pauseSelectedTasks() }
      } label: {
        Label(L10n.tr("action.pause"), systemImage: "pause.fill")
      }
      .disabled(model.selectedTaskIDs.isEmpty)

      Button {
        Task { await model.resumeSelectedTasks() }
      } label: {
        Label(L10n.tr("action.resume"), systemImage: "play.fill")
      }
      .disabled(model.selectedTaskIDs.isEmpty)

      Menu {
        Button(L10n.tr("task.action.remove_only"), role: .destructive) {
          Task { await model.removeSelectedTasks(deletingFiles: false) }
        }
        Button(L10n.tr("task.action.remove_and_trash"), role: .destructive) {
          Task { await model.removeSelectedTasks(deletingFiles: true) }
        }
      } label: {
        Label(L10n.tr("action.remove"), systemImage: "trash")
      }
      .disabled(model.selectedTaskIDs.isEmpty)

      Button(L10n.tr("action.done")) {
        model.endTaskSelection()
      }
      .buttonStyle(.borderedProminent)
      .tint(.teal)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
    }
  }
}

struct StatusPill: View {
  let status: String
  var isSeeding = false

  var body: some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background {
        Capsule()
          .fill(color.opacity(0.13))
      }
  }

  private var title: String {
    if isSeeding { return L10n.tr("task.status.seeding") }
    switch status {
    case "active": return L10n.tr("task.status.downloading")
    case "waiting": return L10n.tr("task.status.waiting")
    case "paused": return L10n.tr("action.pause")
    case "complete": return L10n.tr("action.done")
    case "error": return L10n.tr("task.status.error")
    case "removed": return L10n.tr("task.status.removed")
    default: return status
    }
  }

  private var color: Color {
    switch status {
    case "active": return .teal
    case "waiting": return .secondary
    case "paused": return .orange
    case "complete": return .green
    case "error": return .red
    default: return .secondary
    }
  }
}

struct ErrorBanner: View {
  let text: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)

      Text(text)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)

      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.orange.opacity(0.1))
    }
  }
}
