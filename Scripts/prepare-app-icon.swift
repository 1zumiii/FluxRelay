import AppKit
import ImageIO
import UniformTypeIdentifiers

// Removes only the neutral exterior matte of the generated FluxRelay icon.
guard CommandLine.arguments.count == 3 else {
  fatalError("Usage: swift Scripts/prepare-app-icon.swift input.png output.png")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fatalError("Cannot read source icon")
}
let width = image.width
let height = image.height
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let result: CGImage = pixels.withUnsafeMutableBytes { bytes in
  let context = CGContext(
    data: bytes.baseAddress, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4,
    space: colorSpace, bitmapInfo: bitmapInfo
  )!
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  let rgba = bytes.bindMemory(to: UInt8.self)
  var outside = [Bool](repeating: false, count: width * height)
  var queue = [Int]()
  func visit(_ index: Int) {
    guard !outside[index] else { return }
    let offset = index * 4
    let rgb = [Int(rgba[offset]), Int(rgba[offset + 1]), Int(rgba[offset + 2])]
    guard rgb.min()! > 140, rgb.max()! - rgb.min()! < 28 else { return }
    outside[index] = true
    queue.append(index)
  }
  for x in 0..<width { visit(x); visit((height - 1) * width + x) }
  for y in 0..<height { visit(y * width); visit(y * width + width - 1) }
  var cursor = 0
  while cursor < queue.count {
    let index = queue[cursor]
    cursor += 1
    let x = index % width
    let y = index / width
    if x > 0 { visit(index - 1) }
    if x + 1 < width { visit(index + 1) }
    if y > 0 { visit(index - width) }
    if y + 1 < height { visit(index + width) }
  }
  guard queue.count > width * height / 20, queue.count < width * height / 2 else {
    fatalError("Unexpected exterior matte; inspect this source before processing")
  }
  // Trim one source pixel of matte-contaminated edge before resampling the cutout.
  var clear = outside
  for y in 1..<(height - 1) {
    for x in 1..<(width - 1) {
      let index = y * width + x
      if !outside[index] {
        clear[index] = (-1...1).contains { dy in
          (-1...1).contains { dx in outside[index + dy * width + dx] }
        }
      }
    }
  }
  var minX = width, minY = height, maxX = 0, maxY = 0
  for index in 0..<(width * height) {
    let offset = index * 4
    if clear[index] {
      for channel in 0..<4 { rgba[offset + channel] = 0 }
    } else {
      minX = min(minX, index % width)
      maxX = max(maxX, index % width)
      minY = min(minY, index / width)
      maxY = max(maxY, index / width)
    }
  }
  let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  guard let cutout = context.makeImage()?.cropping(to: bounds) else {
    fatalError("Cannot extract icon")
  }
  let canvas = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: bitmapInfo
  )!
  let scale = 824 / max(bounds.width, bounds.height)
  let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
  canvas.interpolationQuality = .high
  canvas.draw(cutout, in: CGRect(
    x: (1024 - size.width) / 2, y: (1024 - size.height) / 2,
    width: size.width, height: size.height
  ))
  return canvas.makeImage()!
}
guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
  fatalError("Cannot create output icon")
}
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save output icon") }
print(outputURL.path)
