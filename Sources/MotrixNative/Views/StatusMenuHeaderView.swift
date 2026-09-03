import AppKit

@MainActor
final class StatusMenuHeaderView: NSView {
  init(state: String, detail: String, progress: Double?, isError: Bool) {
    super.init(frame: NSRect(x: 0, y: 0, width: 360, height: progress == nil ? 76 : 88))

    let icon = NSImageView(image: NSApp.applicationIconImage)
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.translatesAutoresizingMaskIntoConstraints = false

    let title = label(AppIdentity.displayName, size: 14, weight: .semibold, color: .labelColor)
    let stateLabel = label(state, size: 11, weight: .medium, color: isError ? .systemOrange : .secondaryLabelColor)
    let detailLabel = label(detail, size: 11, weight: .regular, color: .tertiaryLabelColor)
    detailLabel.lineBreakMode = .byTruncatingTail

    [icon, title, stateLabel, detailLabel].forEach(addSubview)

    var constraints = [
      icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      icon.widthAnchor.constraint(equalToConstant: 34),
      icon.heightAnchor.constraint(equalToConstant: 34),
      title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
      title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
      title.topAnchor.constraint(equalTo: topAnchor, constant: 11),
      stateLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
      stateLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
      detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      detailLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8)
    ]

    if let progress {
      let progressView = NSProgressIndicator()
      progressView.style = .bar
      progressView.isIndeterminate = false
      progressView.minValue = 0
      progressView.maxValue = 1
      progressView.doubleValue = min(1, max(0, progress))
      progressView.controlSize = .small
      progressView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(progressView)
      constraints.append(contentsOf: [
        progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
        progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        progressView.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 7),
        progressView.heightAnchor.constraint(equalToConstant: 4)
      ])
    }

    NSLayoutConstraint.activate(constraints)
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
  }
}
