import SwiftUI

struct MainSidebarView: View {
  let selectedSection: MainWindowModel.Section
  let taskCounts: [MainWindowModel.Filter: Int]
  let onSelect: (MainWindowModel.Section) -> Void
  let onOpenDownloads: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(AppIdentity.displayName)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 24)
        .padding(.top, 38)
        .padding(.bottom, 26)

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          navigationGroup(L10n.tr("sidebar.tasks")) {
            ForEach(MainWindowModel.Filter.allCases) { filter in
              SidebarNavigationRow(
                title: filter.title,
                systemImage: filter.sidebarSymbol,
                count: taskCounts[filter, default: 0],
                selected: selectedSection == .tasks(filter)
              ) {
                onSelect(.tasks(filter))
              }
            }
          }

          navigationGroup(L10n.tr("sidebar.settings")) {
            ForEach(MainWindowModel.PreferencesSection.allCases) { section in
              SidebarNavigationRow(
                title: section.title,
                systemImage: section.sidebarSymbol,
                selected: selectedSection == .preferences(section)
              ) {
                onSelect(.preferences(section))
              }
            }
          }
        }
        .padding(.horizontal, 14)
      }
      .scrollIndicators(.hidden)

      SidebarNavigationRow(
        title: L10n.tr("common.downloads_folder"),
        systemImage: "folder",
        action: onOpenDownloads
      )
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, 16)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func navigationGroup<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)

      VStack(spacing: 3, content: content)
    }
  }
}

struct SidebarNavigationRow: View {
  let title: String
  let systemImage: String
  var count: Int? = nil
  var selected = false
  let action: () -> Void
  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: systemImage)
          .font(.system(size: 15, weight: selected ? .semibold : .regular))
          .foregroundStyle(selected ? Color.teal : .secondary)
          .frame(width: 20, height: 20)
          .accessibilityHidden(true)

        Text(title)
          .font(.system(size: 13, weight: selected ? .semibold : .medium))
          .foregroundStyle(.primary.opacity(selected ? 1 : 0.8))
          .lineLimit(1)
          .minimumScaleFactor(0.9)

        Spacer(minLength: 4)

        if let count {
          Text(count.formatted(.number.grouping(.never)))
            .font(.system(size: 11, weight: selected ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(count == 0 ? .tertiary : .secondary)
            .lineLimit(1)
            .frame(minWidth: 16, maxWidth: 32, alignment: .trailing)
        }
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 5)
          .fill(backgroundColor)
      }
      .overlay(alignment: .leading) {
        if selected {
          RoundedRectangle(cornerRadius: 1)
            .fill(.teal)
            .frame(width: 2, height: 14)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityAddTraits(selected ? .isSelected : [])
    .help(title)
  }

  private var backgroundColor: Color {
    if selected {
      return .teal.opacity(colorScheme == .dark ? 0.18 : 0.1)
    }
    return .primary.opacity(isHovered ? 0.045 : 0)
  }
}

private extension MainWindowModel.Filter {
  var sidebarSymbol: String {
    switch self {
    case .all: return "tray.full"
    case .active: return "arrow.down.circle"
    case .waiting: return "clock"
    case .paused: return "pause.circle"
    case .completed: return "checkmark.circle"
    }
  }
}

private extension MainWindowModel.PreferencesSection {
  var sidebarSymbol: String {
    switch self {
    case .general: return "gearshape"
    case .download: return "arrow.down.square"
    case .bittorrent: return "point.3.connected.trianglepath.dotted"
    case .connection: return "network"
    }
  }
}
