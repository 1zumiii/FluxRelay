import SwiftUI

struct DetailSection<Content: View>: View {
  let title: String
  let content: Content
  let lazy: Bool

  init(title: String, lazy: Bool = false, @ViewBuilder content: () -> Content) {
    self.title = title
    self.lazy = lazy
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .padding(.leading, 3)

      Group {
        if lazy {
          LazyVStack(spacing: 0) { content }
        } else {
          VStack(spacing: 0) { content }
        }
      }
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.primary.opacity(0.055), lineWidth: 1)
      }
    }
  }
}

struct DetailRow: View {
  let title: String
  let value: String
  var monospaced = false

  var body: some View {
    HStack(spacing: 14) {
      Text(title)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value)
        .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }
}

struct DetailDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 14)
  }
}

struct DetailEmptyRow: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
  }
}

struct DetailTextRow: View {
  let image: String
  let text: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: image)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(width: 18)
      Text(text)
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}

struct PeerRow: View {
  let peer: Aria2Peer

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: peer.isSeeder ? "arrow.up.circle.fill" : "person.crop.circle")
        .font(.system(size: 15))
        .foregroundStyle(peer.isSeeder ? .indigo : .secondary)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 3) {
        Text(peer.address)
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .lineLimit(1)
        Text(peer.isSeeder ? L10n.tr("task_detail.seeder") : peer.isChoking ? L10n.tr("task_detail.piece_sampled") : L10n.tr("task_detail.transferring"))
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 14)

      VStack(alignment: .trailing, spacing: 3) {
        Label(Formatting.speed(peer.downloadSpeed), systemImage: "arrow.down")
        Label(Formatting.speed(peer.uploadSpeed), systemImage: "arrow.up")
      }
      .font(.system(size: 10, design: .rounded))
      .foregroundStyle(.secondary)
      .monospacedDigit()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
  }
}

struct TaskFileRow: View, Equatable {
  let file: Aria2TaskFile

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: file.isSelected ? "doc.fill" : "doc")
        .font(.system(size: 15))
        .foregroundStyle(file.isSelected ? .teal : .secondary)
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 5) {
        Text(file.name)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
        ProgressView(value: file.progress)
          .tint(.teal)
      }

      Spacer(minLength: 18)

      Text("\(Formatting.bytes(file.completedLength)) / \(Formatting.bytes(file.length))")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}
