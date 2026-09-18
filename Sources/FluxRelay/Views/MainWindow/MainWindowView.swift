import SwiftUI

struct MainWindowView: View {
  @ObservedObject var model: MainWindowModel

  var body: some View {
    HStack(spacing: 0) {
      MainSidebarView(
        selectedSection: model.selectedSection,
        taskCounts: Dictionary(uniqueKeysWithValues: MainWindowModel.Filter.allCases.map {
          ($0, model.count(for: $0))
        }),
        onSelect: model.select,
        onOpenDownloads: model.openDownloadDirectory
      )
      .frame(width: 208)

      Divider()

      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .sheet(isPresented: $model.showingAddTask) {
      AddTaskSheet(model: model)
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 22) {
      if let task = model.selectedTask {
        TaskDetailView(task: task, model: model)
      } else {
        header

        switch model.selectedSection {
        case .preferences(let section):
          PreferencesView(model: model, section: section)
        case .tasks:
          if let errorText = model.errorText {
            ErrorBanner(text: errorText)
          }

          if model.filteredTasks.isEmpty {
            emptyState
          } else {
            taskList
          }
        }
      }
    }
    .padding(.top, 34)
    .padding(.leading, 30)
    .padding(.trailing, 28)
    .padding(.bottom, 28)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text(titleText)
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(.primary)

        Text(subtitleText)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      if case .tasks = model.selectedSection {
        SearchField(text: $model.searchText)
          .frame(width: 240)
      }

      if case .tasks = model.selectedSection {
        Menu {
          Picker(L10n.tr("task.sort.label"), selection: $model.taskSort) {
            ForEach(MainWindowModel.TaskSort.allCases) { sort in
              Text(sort.title).tag(sort)
            }
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 34)
        .help(L10n.tr("task.sort.help"))

        Button {
          model.setTaskSelection(!model.isSelectingTasks)
        } label: {
          Image(systemName: model.isSelectingTasks ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(model.isSelectingTasks ? .teal : nil)
        .help(model.isSelectingTasks ? L10n.tr("task.selection.finish") : L10n.tr("task.selection.start"))
      }

      if case .tasks = model.selectedSection {
        Button {
          model.showingAddTask = true
        } label: {
          Label(L10n.tr("task.action.new"), systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.teal)
      }

      if case .tasks = model.selectedSection {
        Button {
          Task { await model.refresh() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help(L10n.tr("action.refresh"))

        Menu {
          Button {
            Task { await model.clearCompletedTasks() }
          } label: {
            Label(L10n.tr("task.action.clear_completed"), systemImage: "checkmark.circle")
          }
          .disabled(model.count(for: .completed) == 0)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 34)
        .help(L10n.tr("task.action.more"))
      }
    }
  }

  private var titleText: String {
    switch model.selectedSection {
    case .preferences(let section):
      return section.title
    case .tasks(let filter):
      return filter.title
    }
  }

  private var subtitleText: String {
    switch model.selectedSection {
    case .preferences(let section):
      return model.settingsSaved ? L10n.tr("preferences.saved_notice") : section.subtitle
    case .tasks:
      return model.summaryText
    }
  }

  private var taskList: some View {
    VStack(spacing: 10) {
      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(model.filteredTasks) { task in
            TaskCard(task: task, model: model)
          }
        }
        .padding(14)
      }
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor).opacity(0.74))
      }

      if model.isSelectingTasks {
        TaskSelectionBar(model: model)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 42, weight: .regular))
        .foregroundStyle(.tertiary)

      Text(model.searchText.isEmpty ? L10n.tr("task.empty.title") : L10n.tr("task.empty.search_title"))
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.secondary)

      Text(model.searchText.isEmpty ? L10n.tr("task.empty.subtitle") : L10n.tr("task.empty.search_subtitle"))
        .font(.system(size: 13))
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct SearchField: View {
  @Binding var text: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField(L10n.tr("common.search"), text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 15))
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    }
  }
}
