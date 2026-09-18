import AppKit
import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
  static let torrent = UTType(filenameExtension: "torrent") ?? .data
}

struct AddTaskSheet: View {
  @ObservedObject var model: MainWindowModel
  @Environment(\.dismiss) private var dismiss

  @State private var urlText = ""
  @State private var directoryPath: String
  @State private var outputName = ""
  @State private var headers = ""
  @State private var cookie = ""
  @State private var referer = ""
  @State private var checksum = ""
  @State private var pauseAtStart: Bool
  @State private var advancedExpanded = false
  @StateObject private var session: AddTaskSession
  @State private var selectedFileIDs = Set<String>()

  private var preparedTorrent: PreparedTorrent? { session.preparedTorrent }
  private var isPreparingTorrent: Bool { session.isPreparing }

  init(model: MainWindowModel) {
    self.model = model
    self._directoryPath = State(initialValue: model.defaultDownloadDirectory.path)
    self._pauseAtStart = State(initialValue: model.defaultPauseAtStart)
    self._session = StateObject(wrappedValue: AddTaskSession(
      prepare: { await model.prepareTorrent($0, directory: $1) },
      discard: { await model.discardPreparedTorrent($0) },
      addLink: { await model.addLink($0, options: $1) },
      start: { await model.startPreparedTorrent($0, selectedFileIDs: $1, pauseAtStart: $2) }
    ))
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr("add_task.title"))
              .font(.system(size: 22, weight: .semibold))

            Text(L10n.tr("add_task.subtitle"))
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
          }

          VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("add_task.url.title"))
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.secondary)

            TextField(L10n.tr("add_task.url.placeholder"), text: $urlText, axis: .vertical)
              .textFieldStyle(.roundedBorder)
              .lineLimit(3, reservesSpace: true)
              .disabled(preparedTorrent != nil)
          }

          directoryRow
          torrentPicker

          if let preparedTorrent {
            torrentFileSelection(preparedTorrent)
          }

          DisclosureGroup(L10n.tr("add_task.advanced"), isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 12) {
              labeledField(L10n.tr("common.file_name"), placeholder: L10n.tr("add_task.file_name.placeholder"), text: $outputName)
                .disabled(preparedTorrent != nil)
              labeledField(L10n.tr("add_task.referer"), placeholder: "https://example.com/", text: $referer)
              labeledField(L10n.tr("add_task.cookie"), placeholder: "name=value; ...", text: $cookie)
              labeledField(L10n.tr("add_task.checksum"), placeholder: "sha-256=...", text: $checksum)

              VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("add_task.headers"))
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(.secondary)
                TextEditor(text: $headers)
                  .font(.system(size: 11, design: .monospaced))
                  .frame(minHeight: 76)
                  .scrollContentBackground(.hidden)
                  .padding(8)
                  .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                  .overlay {
                    RoundedRectangle(cornerRadius: 6)
                      .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                  }
              }
            }
            .padding(.top, 12)
          }
          .font(.system(size: 13, weight: .medium))

          Toggle(L10n.tr("add_task.pause_after_creation"), isOn: $pauseAtStart)
            .toggleStyle(.switch)
            .font(.system(size: 13, weight: .medium))
        }
        .padding(24)
        .disabled(session.isSubmitting)
      }

      Divider()

      HStack {
        Spacer()

        Button(L10n.tr("action.cancel")) {
          cancel()
        }
        .keyboardShortcut(.cancelAction)
        .disabled(session.isSubmitting)

        Button(L10n.tr("action.add")) {
          submit()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canSubmit || isPreparingTorrent || session.isSubmitting)

        if session.isSubmitting {
          ProgressView().controlSize(.small)
        }
      }
      .padding(16)
    }
    .frame(width: 620, height: preparedTorrent == nil ? 610 : 760)
    .interactiveDismissDisabled(session.isSubmitting)
    .onDisappear {
      Task { await session.close() }
    }
  }

  private var directoryRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.tr("common.destination"))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        TextField(L10n.tr("common.downloads_folder"), text: $directoryPath)
          .textFieldStyle(.roundedBorder)
          .disabled(preparedTorrent != nil)

        Button {
          chooseDirectory()
        } label: {
          Image(systemName: "folder")
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .disabled(preparedTorrent != nil)
        .help(L10n.tr("common.choose_download_directory"))
      }
    }
  }

  private var torrentPicker: some View {
    Button {
      chooseTorrent()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: preparedTorrent == nil ? "doc.badge.plus" : "doc.zipper")
          .font(.system(size: 20))
          .foregroundStyle(.purple)
          .frame(width: 30)

        VStack(alignment: .leading, spacing: 3) {
          Text(preparedTorrent?.sourceURL.lastPathComponent ?? L10n.tr("add_task.torrent.choose"))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(isPreparingTorrent ? L10n.tr("add_task.torrent.reading") : preparedTorrent == nil ? L10n.tr("add_task.torrent.choose_files_hint") : L10n.tr("add_task.torrent.replace_hint"))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }

        Spacer()

        if isPreparingTorrent {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
      }
      .padding(13)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(Color.purple.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color.purple.opacity(0.16), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .disabled(isPreparingTorrent)
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first(where: { $0.pathExtension.lowercased() == "torrent" }) else {
        return false
      }
      loadTorrent(url)
      return true
    }
  }

  private func torrentFileSelection(_ torrent: PreparedTorrent) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text(L10n.format("common.files_count", String(torrent.files.count)))
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button(L10n.tr("action.select_all")) {
          selectedFileIDs = Set(torrent.files.map(\.id))
        }
        .buttonStyle(.link)
        Button(L10n.tr("action.select_none")) {
          selectedFileIDs.removeAll()
        }
        .buttonStyle(.link)
      }

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(torrent.files) { file in
            Toggle(isOn: Binding(
              get: { selectedFileIDs.contains(file.id) },
              set: { selected in
                if selected { selectedFileIDs.insert(file.id) }
                else { selectedFileIDs.remove(file.id) }
              }
            )) {
              HStack {
                Text(file.name)
                  .font(.system(size: 12))
                  .lineLimit(1)
                Spacer()
                Text(Formatting.bytes(file.length))
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
              }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            if file.id != torrent.files.last?.id {
              Divider().padding(.leading, 32)
            }
          }
        }
      }
      .frame(maxHeight: 220)
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color.primary.opacity(0.07), lineWidth: 1)
      }
    }
  }

  private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      TextField(placeholder, text: text)
        .textFieldStyle(.roundedBorder)
    }
  }

  private var canSubmit: Bool {
    if preparedTorrent != nil { return !selectedFileIDs.isEmpty }
    return !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var options: NewDownloadOptions {
    NewDownloadOptions(
      directory: URL(fileURLWithPath: NSString(string: directoryPath).expandingTildeInPath),
      outputName: outputName,
      headers: headers,
      cookie: cookie,
      referer: referer,
      checksum: checksum,
      pauseAtStart: pauseAtStart
    )
  }

  private func chooseTorrent() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.torrent]

    if panel.runModal() == .OK {
      if let url = panel.url {
        loadTorrent(url)
      }
    }
  }

  private func loadTorrent(_ url: URL) {
    guard !session.isPreparing, !session.isSubmitting else { return }
    selectedFileIDs.removeAll()
    urlText = ""
    let directory = options.directory

    Task {
      await session.loadTorrent(url, directory: directory)
      selectedFileIDs = Set(session.preparedTorrent?.files.filter(\.isSelected).map(\.id) ?? [])
    }
  }

  private func chooseDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = options.directory
    if panel.runModal() == .OK, let url = panel.url {
      directoryPath = url.path
    }
  }

  private func cancel() {
    guard !session.isSubmitting else { return }
    Task {
      await session.close()
      dismiss()
    }
  }

  private func submit() {
    let uri = urlText
    let options = options
    let selected = selectedFileIDs
    Task {
      let success = await session.submit(uri: uri, options: options, selectedFileIDs: selected)
      if success {
        dismiss()
      }
    }
  }
}
