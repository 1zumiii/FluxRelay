import SwiftUI

struct PieceMapView: View {
  let input: PieceMapInput
  @State private var snapshot: PieceMapSnapshot?
  @State private var processor = PieceMapProcessor()

  var body: some View {
    PieceMapContent(snapshot: snapshot ?? .unavailable(numPieces: input.numPieces))
      .task(id: input) {
        do {
          let result = try await processor.snapshot(for: input)
          try Task.checkCancellation()
          if snapshot != result { snapshot = result }
        } catch {
          // A newer bitfield or navigation away cancels the obsolete calculation.
        }
      }
  }
}

struct PieceMapContent: View {
  let snapshot: PieceMapSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      if snapshot.samples.isEmpty {
        Text(L10n.tr("task_detail.pieces_unavailable"))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      } else {
        PieceMapCanvas(snapshot: snapshot)
          .equatable()
          .accessibilityLabel(L10n.tr("task_detail.piece_distribution.accessibility"))
          .accessibilityValue(L10n.format(
            "task_detail.pieces_completed_accessibility",
            String(snapshot.completedPieceCount),
            String(snapshot.numPieces)
          ))

        HStack(spacing: 16) {
          PieceLegend(color: .teal, title: L10n.tr("task.status.completed"))
          PieceLegend(color: Color.primary.opacity(0.1), title: L10n.tr("task_detail.piece_incomplete"))
          if snapshot.numPieces > PieceMapSnapshot.maximumSamples {
            PieceLegend(color: .teal.opacity(0.46), title: L10n.tr("task_detail.piece_mixed"))
          }
          Spacer()
          Text("\(snapshot.completedPieceCount) / \(snapshot.numPieces)")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }
}

struct PieceMapCanvas: View, Equatable {
  let snapshot: PieceMapSnapshot
  private let cellSize: CGFloat = 9
  private let spacing: CGFloat = 3

  var body: some View {
    let columns = snapshot.columnCount
    let rows = snapshot.rowCount
    Canvas(rendersAsynchronously: true) { context, _ in
      for (index, ratio) in snapshot.samples.enumerated() {
        let rect = CGRect(
          x: CGFloat(index % columns) * (cellSize + spacing),
          y: CGFloat(index / columns) * (cellSize + spacing),
          width: cellSize,
          height: cellSize
        )
        let color: Color = ratio >= 1 ? .teal
          : ratio <= 0 ? Color.primary.opacity(0.1) : .teal.opacity(0.3 + ratio * 0.5)
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
      }
    }
    .frame(
      width: CGFloat(columns) * cellSize + CGFloat(max(0, columns - 1)) * spacing,
      height: CGFloat(rows) * cellSize + CGFloat(max(0, rows - 1)) * spacing
    )
  }
}

private struct PieceLegend: View {
  let color: Color
  let title: String

  var body: some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(color)
        .frame(width: 8, height: 8)
      Text(title)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
  }
}
