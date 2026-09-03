import AppKit
import SwiftUI
import XCTest
@testable import MotrixNative

@MainActor
final class PieceMapRenderingTests: XCTestCase {
  func testNativeCanvasRendersLightAndDarkAtRetinaScale() throws {
    let snapshot = try PieceMapSnapshot.build(numPieces: 960, bitfield: String(repeating: "f0a5", count: 60))
    for (name, scheme, background) in [("light", ColorScheme.light, Color.white), ("dark", .dark, Color.black)] {
      let content = PieceMapCanvas(snapshot: snapshot)
        .padding(14)
        .frame(width: 600, alignment: .leading)
        .background(background)
        .environment(\.colorScheme, scheme)
      let renderer = ImageRenderer(content: content)
      renderer.scale = 2
      let image = try XCTUnwrap(renderer.cgImage)
      XCTAssertEqual(image.width, 1200)
      XCTAssertGreaterThan(image.height, 200)
      let bitmap = NSBitmapImageRep(cgImage: image)
      let completed = try XCTUnwrap(bitmap.colorAt(x: 37, y: 37)?.usingColorSpace(.deviceRGB))
      let incomplete = try XCTUnwrap(bitmap.colorAt(x: 85, y: 37)?.usingColorSpace(.deviceRGB))
      let mixed = try XCTUnwrap(bitmap.colorAt(x: 133, y: 37)?.usingColorSpace(.deviceRGB))
      XCTAssertGreaterThan(completed.greenComponent - completed.redComponent, 0.1)
      XCTAssertNotEqual(completed, incomplete)
      XCTAssertNotEqual(mixed, incomplete)
      XCTAssertNotEqual(mixed, completed)
      if let directory = ProcessInfo.processInfo.environment["MOTRIX_RENDER_CHECK_DIR"] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("piece-map-\(name).png"))
      }
    }
  }
}
