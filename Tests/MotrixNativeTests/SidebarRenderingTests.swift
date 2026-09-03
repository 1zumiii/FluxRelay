import AppKit
import SwiftUI
import XCTest
@testable import MotrixNative

@MainActor
final class SidebarRenderingTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
  }

  func testSidebarAtCompactHeightInBothLanguagesAndAppearances() throws {
    let resources = try XCTUnwrap(Bundle(url: root.appendingPathComponent("Resources/Localization")))
    defer { L10n.configure(language: "system") }

    for language in ["en", "zh-Hans"] {
      L10n.configure(language: language, bundle: resources)
      XCTAssertNotEqual(L10n.tr("sidebar.tasks"), "sidebar.tasks")
      for (name, scheme, background) in [("light", ColorScheme.light, Color.white), ("dark", .dark, Color.black)] {
        let content = HStack(spacing: 0) {
          MainSidebarView(
            selectedSection: .tasks(.active),
            taskCounts: [.all: 12, .active: 2, .completed: 10],
            onSelect: { _ in }, onOpenDownloads: {}
          )
          .frame(width: 208)
          Divider()
          background.frame(width: 16)
        }
        .frame(height: 540)
        .background(background)
        .environment(\.colorScheme, scheme)
        let bitmap = try renderHosted(content, size: NSSize(width: 225, height: 540))
        XCTAssertEqual(bitmap.pixelsHigh, 1080)
        let outside = try XCTUnwrap(bitmap.colorAt(x: 8, y: 500)?.usingColorSpace(.deviceRGB))
        let emptyInside = try XCTUnwrap(bitmap.colorAt(x: 90, y: 910)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(outside.redComponent, emptyInside.redComponent, accuracy: 0.01)
        XCTAssertEqual(outside.greenComponent, emptyInside.greenComponent, accuracy: 0.01)
        try save(bitmap, name: "sidebar-\(language)-\(name)")
      }
    }
  }

  func testRowsKeepTheirDimensionsWithLongLabelsAndCounts() throws {
    for count in [0, 42, 123456] {
      for selected in [false, true] {
        let renderer = ImageRenderer(content: SidebarNavigationRow(
          title: "Downloading", systemImage: "arrow.down.circle", count: count,
          selected: selected, action: {}
        ).frame(width: 180))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 360)
        XCTAssertEqual(image.height, 64)
      }
    }
  }

  func testAppIconHasTransparentMarginsAndOpaqueArtwork() throws {
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/AppIcon.png"))
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
    XCTAssertEqual(bitmap.pixelsWide, 1024)
    XCTAssertEqual(bitmap.pixelsHigh, 1024)
    for (x, y) in [(0, 0), (1023, 0), (0, 1023), (1023, 1023), (512, 40), (40, 512)] {
      XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0)
    }
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 512, y: 512)).alphaComponent, 1)
  }

  func testNavigationRowKeepsItsBackgroundInsideTheHitRegion() {
    let view = NSHostingView(rootView: SidebarNavigationRow(
      title: "Downloading", systemImage: "arrow.down.circle", count: 2,
      selected: true, action: {}
    ).frame(width: 180))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 180, height: 32),
      styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.contentView = view
    window.layoutIfNeeded()
    view.layoutSubtreeIfNeeded()
    for point in [NSPoint(x: 2, y: 2), NSPoint(x: 178, y: 30), NSPoint(x: 135, y: 16)] {
      XCTAssertNotNil(view.hitTest(point))
    }
    XCTAssertNil(view.hitTest(NSPoint(x: 181, y: 16)))
  }

  private func renderHosted<Content: View>(_ content: Content, size: NSSize) throws -> NSBitmapImageRep {
    let view = NSHostingView(rootView: content)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    window.layoutIfNeeded()
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    bitmap.size = size
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
  }

  private func save(_ bitmap: NSBitmapImageRep, name: String) throws {
    guard let path = ProcessInfo.processInfo.environment["FLUXRELAY_RENDER_CHECK_DIR"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: directory.appendingPathComponent("\(name).png"))
  }
}
