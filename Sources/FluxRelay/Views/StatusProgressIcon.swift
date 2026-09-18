import AppKit

struct ProgressSummary {
  let progress: Double
  let taskCount: Int
  let hasIncompleteTasks: Bool

  var percent: Int {
    Int((min(1, max(0, progress)) * 100).rounded())
  }

  var statusTitle: String {
    guard hasIncompleteTasks else {
      return ""
    }

    if taskCount > 1 {
      return "\(taskCount) \(percent)%"
    }

    return "\(percent)%"
  }
}

enum StatusProgressIcon {
  private static let size = NSSize(width: 18, height: 18)
  private static let progressColor = NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.54, alpha: 1)
  private static let completeColor = NSColor(calibratedRed: 0.18, green: 0.64, blue: 0.35, alpha: 1)
  private static let trackColor = NSColor(calibratedWhite: 0.68, alpha: 0.42)

  static func renderError() -> NSImage {
    coloredSymbol("exclamationmark.circle.fill", color: .systemOrange)
  }

  static func renderCompletion() -> NSImage {
    coloredSymbol("checkmark.circle.fill", color: completeColor)
  }

  static func render(_ summary: ProgressSummary?) -> NSImage {
    guard let summary else {
      return templateSymbol("arrow.down.circle")
    }

    if !summary.hasIncompleteTasks && summary.percent >= 100 {
      return renderCompletion()
    }

    let image = NSImage(size: size, flipped: false) { rect in
      let center = NSPoint(x: rect.midX, y: rect.midY)
      let radius = min(rect.width, rect.height) * 0.39
      let lineWidth = min(rect.width, rect.height) * 0.14

      let track = NSBezierPath()
      track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
      track.lineWidth = lineWidth
      trackColor.setStroke()
      track.stroke()

      let progress = min(1, max(0, summary.progress))
      if progress > 0 {
        let arc = NSBezierPath()
        arc.appendArc(
          withCenter: center,
          radius: radius,
          startAngle: 90,
          endAngle: 90 - (360 * progress),
          clockwise: true
        )
        arc.lineCapStyle = .round
        arc.lineWidth = lineWidth
        progressColor.setStroke()
        arc.stroke()
      }

      let innerRect = rect.insetBy(dx: rect.width * 0.29, dy: rect.height * 0.29)
      drawSymbol("arrow.down", in: innerRect, color: NSColor(calibratedWhite: 0.58, alpha: 0.95))
      return true
    }
    image.isTemplate = false
    return image
  }

  private static func templateSymbol(_ name: String) -> NSImage {
    guard let symbol = configuredSymbol(name, pointSize: 17, weight: .semibold) else {
      return NSImage(size: size)
    }
    symbol.isTemplate = true
    return symbol
  }

  private static func coloredSymbol(_ name: String, color: NSColor) -> NSImage {
    let image = NSImage(size: size, flipped: false) { rect in
      drawSymbol(name, in: rect, color: color, pointSize: 17, weight: .semibold)
      return true
    }
    image.isTemplate = false
    return image
  }

  private static func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
    drawSymbol(name, in: rect, color: color, pointSize: rect.height, weight: .bold)
  }

  private static func drawSymbol(
    _ name: String,
    in rect: NSRect,
    color: NSColor,
    pointSize: CGFloat,
    weight: NSFont.Weight
  ) {
    guard let symbol = configuredSymbol(name, pointSize: pointSize, weight: weight) else {
      return
    }

    symbol.draw(in: rect)
    color.setFill()
    rect.fill(using: .sourceAtop)
  }

  private static func configuredSymbol(
    _ name: String,
    pointSize: CGFloat,
    weight: NSFont.Weight
  ) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard
      let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
      let configured = symbol.withSymbolConfiguration(configuration)
    else {
      return nil
    }
    configured.size = size
    return configured
  }
}
