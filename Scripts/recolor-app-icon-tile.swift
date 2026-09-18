import AppKit
import ImageIO
import UniformTypeIdentifiers

// Replaces the emerald tile of the prepared FluxRelay icon with a charcoal tile,
// keeping the tile silhouette, the ribbon symbol and its contact shadow.
guard CommandLine.arguments.count == 3 else {
  fatalError("Usage: swift Scripts/recolor-app-icon-tile.swift emerald.png output.png")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == 1024, image.height == 1024 else {
  fatalError("Expected the 1024-pixel master produced by Scripts/prepare-app-icon.swift")
}

let size = 1024
let count = size * size
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
var bytes = [UInt8](repeating: 0, count: count * 4)
bytes.withUnsafeMutableBytes { buffer in
  let context = CGContext(
    data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
}

// Unpremultiplied colour channels in 0...1; row 0 is the top of the icon.
var red = [Float](repeating: 0, count: count)
var green = [Float](repeating: 0, count: count)
var blue = [Float](repeating: 0, count: count)
var alpha = [Float](repeating: 0, count: count)
for index in 0..<count {
  let a = Float(bytes[index * 4 + 3]) / 255
  alpha[index] = a
  guard a > 0 else { continue }
  red[index] = min(1, Float(bytes[index * 4]) / 255 / a)
  green[index] = min(1, Float(bytes[index * 4 + 1]) / 255 / a)
  blue[index] = min(1, Float(bytes[index * 4 + 2]) / 255 / a)
}

func integral(_ values: [Float]) -> [Double] {
  var table = [Double](repeating: 0, count: (size + 1) * (size + 1))
  for y in 0..<size {
    var row = 0.0
    for x in 0..<size {
      row += Double(values[y * size + x])
      table[(y + 1) * (size + 1) + x + 1] = table[y * (size + 1) + x + 1] + row
    }
  }
  return table
}

func boxSum(_ table: [Double], _ x: Int, _ y: Int, _ radius: Int) -> Double {
  let x0 = max(0, x - radius), y0 = max(0, y - radius)
  let x1 = min(size, x + radius + 1), y1 = min(size, y + radius + 1)
  let w = size + 1
  return table[y1 * w + x1] - table[y0 * w + x1] - table[y1 * w + x0] + table[y0 * w + x0]
}

func boxArea(_ x: Int, _ y: Int, _ radius: Int) -> Double {
  Double((min(size, x + radius + 1) - max(0, x - radius)) * (min(size, y + radius + 1) - max(0, y - radius)))
}

// The emerald tile has almost no red, while the ivory ribbon and its mint fold do.
let symbol = red.indices.map { alpha[$0] > 0.99 && red[$0] > 0.2 ? Float(1) : 0 }
let opaque = alpha.map { $0 > 0.99 ? Float(1) : 0 }
let symbolTable = integral(symbol)
let opaqueTable = integral(opaque)

var core = [Bool](repeating: false, count: count)
var band = [Bool](repeating: false, count: count)
var cleanTile = [Bool](repeating: false, count: count)
for y in 0..<size {
  for x in 0..<size {
    let index = y * size + x
    let nearbySymbol = boxSum(symbolTable, x, y, 3)
    core[index] = boxSum(symbolTable, x, y, 2) == boxArea(x, y, 2)
    band[index] = !core[index] && nearbySymbol > 0
    cleanTile[index] = boxSum(opaqueTable, x, y, 28) == boxArea(x, y, 28)
      && boxSum(symbolTable, x, y, 64) == 0
  }
}

// Fit the tile's lighting as a quadratic surface so shadows can be measured against it.
func fitSurface(_ channel: [Float]) -> (Double, Double) -> Double {
  var normal = [[Double]](repeating: [Double](repeating: 0, count: 7), count: 6)
  for y in stride(from: 0, to: size, by: 4) {
    for x in stride(from: 0, to: size, by: 4) where cleanTile[y * size + x] {
      let u = Double(x) / Double(size) * 2 - 1, v = Double(y) / Double(size) * 2 - 1
      let terms = [1, u, v, u * u, u * v, v * v]
      for row in 0..<6 {
        for column in 0..<6 { normal[row][column] += terms[row] * terms[column] }
        normal[row][6] += terms[row] * Double(channel[y * size + x])
      }
    }
  }
  for pivot in 0..<6 {
    let best = (pivot..<6).max { abs(normal[$0][pivot]) < abs(normal[$1][pivot]) }!
    normal.swapAt(pivot, best)
    for row in 0..<6 where row != pivot {
      let factor = normal[row][pivot] / normal[pivot][pivot]
      for column in pivot..<7 { normal[row][column] -= factor * normal[pivot][column] }
    }
  }
  let coefficients = (0..<6).map { normal[$0][6] / normal[$0][$0] }
  return { u, v in
    zip(coefficients, [1, u, v, u * u, u * v, v * v]).reduce(0) { $0 + $1.0 * $1.1 }
  }
}
let baseRed = fitSurface(red)
let baseGreen = fitSurface(green)

// Shading of the tile relative to its lighting: < 1 is the ribbon's contact shadow,
// > 1 is the lit rim along the tile edge.
var shade = [Float](repeating: 1, count: count)
var shadeWeight = [Float](repeating: 0, count: count)
for y in 0..<size {
  for x in 0..<size {
    let index = y * size + x
    guard alpha[index] > 0, !core[index], !band[index] else { continue }
    let u = Double(x) / Double(size) * 2 - 1, v = Double(y) / Double(size) * 2 - 1
    shade[index] = Float(min(1.6, max(0, Double(green[index]) / max(0.05, baseGreen(u, v)))))
    shadeWeight[index] = 1
  }
}
let shadeTable = integral(zip(shade, shadeWeight).map { $0 * $1 })
let shadeWeightTable = integral(shadeWeight)
let coreFlags = core.map { $0 ? Float(1) : 0 }
let coreTable = integral(coreFlags)
let coreRedTable = integral(zip(red, coreFlags).map { $0 * $1 })
let coreGreenTable = integral(zip(green, coreFlags).map { $0 * $1 })
let coreBlueTable = integral(zip(blue, coreFlags).map { $0 * $1 })

func charcoal(_ x: Int, _ y: Int) -> (Float, Float, Float) {
  // Light falls from the upper left, like the original enamel tile.
  let u = Float(x) / Float(size), v = Float(y) / Float(size)
  let t = min(1, max(0, 0.72 * v + 0.28 * u - 0.08))
  let top: (Float, Float, Float) = (0.200, 0.200, 0.212)
  let bottom: (Float, Float, Float) = (0.043, 0.043, 0.051)
  return (top.0 + (bottom.0 - top.0) * t, top.1 + (bottom.1 - top.1) * t, top.2 + (bottom.2 - top.2) * t)
}

func shaded(_ tile: (Float, Float, Float), _ factor: Float) -> (Float, Float, Float) {
  if factor < 1 {
    let darken = 1 - (1 - factor) * 1.15
    return (tile.0 * max(0, darken), tile.1 * max(0, darken), tile.2 * max(0, darken))
  }
  let lift = (factor - 1) * 0.16
  return (tile.0 + lift, tile.1 + lift, tile.2 + lift)
}

var output = [UInt8](repeating: 0, count: count * 4)
for y in 0..<size {
  for x in 0..<size {
    let index = y * size + x
    guard alpha[index] > 0 else { continue }
    let tile = charcoal(x, y)
    var color: (Float, Float, Float)
    if core[index] {
      color = (red[index], green[index], blue[index])
    } else if band[index] {
      // Anti-aliased ribbon edge: unmix the ribbon colour from the emerald behind it.
      let coreCount = boxSum(coreTable, x, y, 5)
      let symbolColor: (Float, Float, Float) = coreCount > 0
        ? (Float(boxSum(coreRedTable, x, y, 5) / coreCount),
           Float(boxSum(coreGreenTable, x, y, 5) / coreCount),
           Float(boxSum(coreBlueTable, x, y, 5) / coreCount))
        : (0.96, 0.94, 0.90)
      let weight = boxSum(shadeWeightTable, x, y, 6)
      let localShade = weight > 0 ? Float(boxSum(shadeTable, x, y, 6) / weight) : 1
      let u = Double(x) / Double(size) * 2 - 1, v = Double(y) / Double(size) * 2 - 1
      let behind = Float(baseRed(u, v)) * min(1, localShade)
      let coverage = min(1, max(0, (red[index] - behind) / max(0.05, symbolColor.0 - behind)))
      let back = shaded(tile, localShade)
      color = (
        symbolColor.0 * coverage + back.0 * (1 - coverage),
        symbolColor.1 * coverage + back.1 * (1 - coverage),
        symbolColor.2 * coverage + back.2 * (1 - coverage)
      )
    } else {
      color = shaded(tile, shade[index])
    }
    let a = alpha[index]
    output[index * 4] = UInt8(min(1, max(0, color.0)) * a * 255 + 0.5)
    output[index * 4 + 1] = UInt8(min(1, max(0, color.1)) * a * 255 + 0.5)
    output[index * 4 + 2] = UInt8(min(1, max(0, color.2)) * a * 255 + 0.5)
    output[index * 4 + 3] = bytes[index * 4 + 3]
  }
}

let result: CGImage = output.withUnsafeMutableBytes { buffer in
  CGContext(
    data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!.makeImage()!
}
guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
  fatalError("Cannot create output icon")
}
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save output icon") }
print(outputURL.path)
