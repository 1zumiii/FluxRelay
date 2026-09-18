import SwiftUI

struct TaskDetailView: View {
  let task: Aria2Task
  @ObservedObject var model: MainWindowModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      detailHeader

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          progressSection

          if task.numPieces > 0 {
            pieceMapSection
          }

          HStack(alignment: .top, spacing: 18) {
            DetailSection(title: L10n.tr("task_detail.transfer")) {
              DetailRow(title: L10n.tr("transfer.download_speed"), value: Formatting.speed(task.downloadSpeed))
              DetailDivider()
              DetailRow(title: L10n.tr("transfer.upload_speed"), value: Formatting.speed(task.uploadSpeed))
              DetailDivider()
              DetailRow(title: L10n.tr("transfer.downloaded"), value: Formatting.bytes(task.completedLength))
              DetailDivider()
              DetailRow(title: L10n.tr("transfer.uploaded"), value: Formatting.bytes(task.uploadLength))
              if task.isBitTorrent {
                DetailDivider()
                DetailRow(title: L10n.tr("bittorrent.seed_ratio"), value: shareRatioText)
              }
              DetailDivider()
              DetailRow(title: L10n.tr("task_detail.active_connections"), value: "\(task.connections)")
            }
            .frame(maxWidth: .infinity)

            DetailSection(title: L10n.tr("task_detail.information")) {
              DetailRow(
                title: L10n.tr("task_detail.type"),
                value: task.isBitTorrent ? L10n.tr("task.type.bittorrent") : L10n.tr("task.type.http_ftp")
              )
              DetailDivider()
              DetailRow(title: L10n.tr("task_detail.pieces"), value: task.numPieces > 0 ? "\(task.numPieces) × \(Formatting.bytes(task.pieceLength))" : "-")
              DetailDivider()
              DetailRow(title: L10n.tr("preferences.split.title"), value: effectiveOption("split"))
              DetailDivider()
              DetailRow(title: L10n.tr("task_detail.connections_per_server"), value: effectiveOption("max-connection-per-server"))
              DetailDivider()
              DetailRow(title: L10n.tr("task_detail.server"), value: task.sourceHost ?? "-")
              DetailDivider()
              DetailRow(title: L10n.tr("task_detail.gid"), value: task.id, monospaced: true)
              if let completionDate = task.completionDate {
                DetailDivider()
                DetailRow(title: L10n.tr("task_detail.completed_at"), value: Formatting.date(completionDate))
              }
              DetailDivider()
              DetailRow(title: L10n.tr("task_detail.checksum_result"), value: task.checksumResult.title)
              if let checksum = task.checksum, !checksum.isEmpty {
                DetailDivider()
                DetailRow(title: L10n.tr("add_task.checksum"), value: checksum, monospaced: true)
              }
            }
            .frame(maxWidth: .infinity)
          }

          if task.status == "error" {
            HStack(alignment: .top, spacing: 10) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
              VStack(alignment: .leading, spacing: 3) {
                Text(L10n.format("task_detail.error_code", task.errorCode))
                  .font(.system(size: 13, weight: .semibold))
                Text(task.errorMessage.isEmpty ? L10n.tr("task_detail.no_error_details") : task.errorMessage)
                  .font(.system(size: 12))
                  .foregroundStyle(.secondary)
              }
              Spacer()
            }
            .padding(14)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          }

          if task.isBitTorrent {
            bitTorrentSummary
            trackerSection
            peerSection
          }

          filesSection

          DetailSection(title: L10n.tr("task_detail.location_and_source")) {
            DetailRow(title: L10n.tr("common.destination"), value: task.directory.isEmpty ? (task.primaryFileURL?.path ?? "-") : task.directory)
            if let sourceURI = task.sourceURI {
              DetailDivider()
              DetailRow(title: L10n.tr("task_detail.source"), value: sourceURI)
            }
          }
        }
        .padding(.trailing, 10)
        .padding(.bottom, 24)
      }
    }
  }

  private var detailHeader: some View {
    HStack(spacing: 14) {
      Button {
        model.closeDetails()
      } label: {
        Image(systemName: "chevron.left")
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .help(L10n.tr("task_detail.back"))

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 9) {
          Text(task.name)
            .font(.system(size: 24, weight: .semibold))
            .lineLimit(1)
          StatusPill(status: task.status, isSeeding: task.isSeeding)
        }
        Text(task.primaryFileURL?.deletingLastPathComponent().path ?? task.id)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      if task.status == "active" {
        Button {
          Task { await model.pause(task) }
        } label: {
          Label(L10n.tr("action.pause"), systemImage: "pause.fill")
        }
      } else if task.status == "paused" || task.status == "waiting" {
        Button {
          Task { await model.resume(task) }
        } label: {
          Label(L10n.tr("action.resume"), systemImage: "play.fill")
        }
      }

      Button {
        model.reveal(task)
      } label: {
        Image(systemName: "folder")
      }
      .help(L10n.tr("task.action.reveal_file"))

      Menu {
        Button(L10n.tr("task_detail.copy_gid")) {
          model.copyGID(task)
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
        Button(L10n.tr("task.action.remove"), role: .destructive) {
          Task { await model.remove(task) }
        }
        Button(L10n.tr("task.action.remove_and_trash"), role: .destructive) {
          Task { await model.remove(task, deletingFiles: true) }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .frame(width: 30)
    }
  }

  private var progressSection: some View {
    HStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(statusColor.opacity(0.14))
        Image(systemName: task.isSeeding ? "arrow.up.circle.fill" : task.status == "complete" ? "checkmark.circle.fill" : "arrow.down.circle.fill")
          .font(.system(size: 25, weight: .semibold))
          .foregroundStyle(statusColor)
      }
      .frame(width: 54, height: 54)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(task.isSeeding ? L10n.tr("task_detail.seeding_status") : task.localizedStatus)
            .font(.system(size: 14, weight: .semibold))
          Spacer()
          Text("\(Int((task.progress * 100).rounded()))%")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .monospacedDigit()
        }

        ProgressView(value: task.progress)
          .tint(statusColor)

        Text("\(Formatting.bytes(task.completedLength)) / \(Formatting.bytes(task.totalLength))")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.primary.opacity(0.055), lineWidth: 1)
    }
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

  private var shareRatioText: String {
    guard task.completedLength > 0 else { return "0.00" }
    return String(format: "%.2f", Double(task.uploadLength) / Double(task.completedLength))
  }

  private var pieceMapSection: some View {
    DetailSection(title: L10n.tr("task_detail.piece_distribution")) {
      PieceMapView(input: PieceMapInput(taskID: task.id, numPieces: task.numPieces, bitfield: task.bitfield))
        .id(task.id)
    }
  }

  private var filesSection: some View {
    let files = task.fileDetails
    return DetailSection(
      title: files.count > 1
        ? L10n.format("common.files_count", String(files.count))
        : L10n.tr("common.files"),
      lazy: true
    ) {
      ForEach(files) { file in
        VStack(spacing: 0) {
          TaskFileRow(file: file).equatable()
          if file.id != files.last?.id { DetailDivider() }
        }
      }
    }
  }

  private func effectiveOption(_ key: String) -> String {
    model.selectedTaskOptions[key] ?? (task.isTerminal ? "—" : L10n.tr("common.loading"))
  }

  private var bitTorrentSummary: some View {
    DetailSection(title: L10n.tr("task_detail.bittorrent_network")) {
      DetailRow(title: L10n.tr("task_detail.info_hash"), value: task.infoHash.isEmpty ? "-" : task.infoHash, monospaced: true)
      DetailDivider()
      DetailRow(title: L10n.tr("task_detail.tracker"), value: "\(task.trackers.count)")
      DetailDivider()
      DetailRow(title: L10n.tr("task_detail.peer"), value: "\(model.selectedPeers.count)")
      DetailDivider()
      DetailRow(title: L10n.tr("task_detail.seeder"), value: "\(model.selectedPeers.filter(\.isSeeder).count)")
    }
  }

  private var trackerSection: some View {
    DetailSection(title: L10n.format("task_detail.trackers_count", String(task.trackers.count))) {
      if task.trackers.isEmpty {
        DetailEmptyRow(text: L10n.tr("task_detail.no_trackers"))
      } else {
        ForEach(Array(task.trackers.prefix(8).enumerated()), id: \.offset) { index, tracker in
          DetailTextRow(image: "antenna.radiowaves.left.and.right", text: tracker)
          if index < min(task.trackers.count, 8) - 1 {
            DetailDivider()
          }
        }

        if task.trackers.count > 8 {
          DetailDivider()
          DetailEmptyRow(text: L10n.format("task_detail.more_trackers", String(task.trackers.count - 8)))
        }
      }
    }
  }

  private var peerSection: some View {
    DetailSection(title: L10n.format("task_detail.peers_count", String(model.selectedPeers.count))) {
      if model.selectedPeers.isEmpty {
        DetailEmptyRow(text: task.status == "active" ? L10n.tr("task_detail.waiting_for_peers") : L10n.tr("task_detail.no_peers"))
      } else {
        ForEach(Array(model.selectedPeers.prefix(20).enumerated()), id: \.offset) { index, peer in
          PeerRow(peer: peer)
          if index < min(model.selectedPeers.count, 20) - 1 {
            DetailDivider()
          }
        }

        if model.selectedPeers.count > 20 {
          DetailDivider()
          DetailEmptyRow(text: L10n.format("task_detail.more_peers", String(model.selectedPeers.count - 20)))
        }
      }
    }
  }
}
