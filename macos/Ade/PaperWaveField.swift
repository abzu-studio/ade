import CoreGraphics
import Foundation

/// Soft crest light for the paper field.
///
/// 0.4.5 blurred two fills and two strokes at the full window size on every frame.
/// A kernel profile put that at about 9 ms per blur at 1× and about 96 ms at retina 2×,
/// so four of them missed a 30 fps budget. The crest geometry is unchanged; it is drawn
/// into a buffer whose long edge is at most 420 points and blurred there in C.
/// The ordered dither is the same formula, stamped into one image instead of a SwiftUI path.
enum PaperWaveField {
  static func image(
    size: CGSize, time: Double, energy: Double, night: Bool,
    red: CGFloat, green: CGFloat, blue: CGFloat
  ) -> CGImage? {
    Cache.shared.image(
      size: size, time: time, energy: energy, night: night, red: red, green: green, blue: blue)
  }
}

private final class Cache: @unchecked Sendable {
  static let shared = Cache()
  private let lock = NSLock()
  private var width = 0
  private var height = 0
  private var capacity = 0
  private var layer: UnsafeMutablePointer<UInt8>?
  private var temp: UnsafeMutablePointer<UInt8>?
  private var output: UnsafeMutablePointer<UInt8>?
  private var layerContext: CGContext?

  func image(
    size: CGSize, time: Double, energy: Double, night: Bool,
    red: CGFloat, green: CGFloat, blue: CGFloat
  ) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    let longest = max(size.width, size.height)
    guard longest > 1, size.width > 1, size.height > 1 else { return nil }
    let fit = min(1, 420 / longest)
    let pixelWidth = max(2, Int((size.width * fit).rounded()))
    let pixelHeight = max(2, Int((size.height * fit).rounded()))
    ensure(width: pixelWidth, height: pixelHeight)
    guard let layer, let output, let ctx = layerContext else { return nil }
    let bytes = pixelWidth * pixelHeight * 4
    output.assign(repeating: 0, count: bytes)
    let blurPoints = min(54, max(24, size.height * 0.055))
    let radius = max(1, Int((blurPoints * Double(pixelHeight) / Double(size.height)).rounded()))
    let strokeRadius = max(1, Int((Double(radius) * 0.8).rounded()))
    let phase = time * Double.pi * 2
    let fillAlpha = (night ? 0.18 : 0.14) * energy
    let whiteAlpha = (night ? 0.075 : 0.48) * energy
    let inkAlpha = night ? 0.22 : 0.08
    for band in 0..<2 {
      let offset = Double(band) * Double.pi
      let crest = crestPath(
        width: CGFloat(pixelWidth), height: CGFloat(pixelHeight),
        phase: phase, energy: energy, offset: offset, band: band)
      paint(fill: crest, into: ctx, pixels: layer, bytes: bytes, red: red, green: green, blue: blue, alpha: fillAlpha)
      blur(layer, pixelWidth, pixelHeight, radius)
      composite(layer, output, pixelWidth * pixelHeight)
      paintStroke(
        crest, into: ctx, pixels: layer, bytes: bytes,
        width: CGFloat(pixelWidth), height: CGFloat(pixelHeight),
        red: red, green: green, blue: blue, whiteAlpha: whiteAlpha, inkAlpha: inkAlpha)
      blur(layer, pixelWidth, pixelHeight, strokeRadius)
      composite(layer, output, pixelWidth * pixelHeight)
    }
    return copyImage(output, pixelWidth, pixelHeight)
  }

  private func crestPath(
    width: CGFloat, height: CGFloat, phase: Double, energy: Double, offset: Double, band: Int
  ) -> CGMutablePath {
    let path = CGMutablePath()
    for column in 0...64 {
      let u = Double(column) / 64
      let x = (u * 1.16 - 0.08) * Double(width)
      let swell = 0.065 * sin(u * .pi * 2 - phase / 12 + offset)
        + 0.035 * sin(u * .pi * 3 + phase / 20 + offset)
      let drift = 0.09 * sin(phase / 10 + offset)
      let y = Double(height) * (0.62 + Double(band) * 0.20 + energy * (swell + drift))
      let point = CGPoint(x: x, y: y)
      if column == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    return path
  }

  private func paint(
    fill crest: CGMutablePath, into ctx: CGContext, pixels: UnsafeMutablePointer<UInt8>, bytes: Int,
    red: CGFloat, green: CGFloat, blue: CGFloat, alpha: Double
  ) {
    pixels.assign(repeating: 0, count: bytes)
    let depth = CGMutablePath()
    depth.addPath(crest)
    depth.addLine(to: CGPoint(x: CGFloat(width) * 1.08, y: CGFloat(height) * 1.2))
    depth.addLine(to: CGPoint(x: -CGFloat(width) * 0.08, y: CGFloat(height) * 1.2))
    depth.closeSubpath()
    ctx.saveGState()
    ctx.addPath(depth)
    ctx.setFillColor(shade(red, green, blue, alpha))
    ctx.fillPath()
    ctx.restoreGState()
  }

  private func paintStroke(
    _ crest: CGMutablePath, into ctx: CGContext, pixels: UnsafeMutablePointer<UInt8>, bytes: Int,
    width: CGFloat, height: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat,
    whiteAlpha: Double, inkAlpha: Double
  ) {
    pixels.assign(repeating: 0, count: bytes)
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [
      shade(red, green, blue, 0),
      shade(1, 1, 1, whiteAlpha),
      shade(red, green, blue, inkAlpha),
      shade(red, green, blue, 0),
    ] as CFArray
    let locations: [CGFloat] = [0, 0.35, 0.70, 1]
    guard let gradient = locations.withUnsafeBufferPointer({ buffer in
      CGGradient(colorsSpace: space, colors: colors, locations: buffer.baseAddress)
    }) else { return }
    ctx.saveGState()
    ctx.addPath(crest)
    ctx.setLineWidth(height * 0.10)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
      gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    ctx.restoreGState()
  }

  private func shade(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: Double) -> CGColor {
    let parts = [red, green, blue, CGFloat(alpha)]
    if let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: parts) {
      return color
    }
    return CGColor(gray: 0, alpha: 0)
  }

  /// Three box passes. The loop lives in C so a debug build does not interpret it per pixel.
  private func blur(_ pixels: UnsafeMutablePointer<UInt8>, _ w: Int, _ h: Int, _ radius: Int) {
    guard let temp else { return }
    ade_box_blur_rgba(pixels, temp, Int32(w), Int32(h), Int32(radius))
  }

  private func composite(_ src: UnsafePointer<UInt8>, _ dst: UnsafeMutablePointer<UInt8>, _ pixels: Int) {
    for index in 0..<pixels {
      let offset = index * 4
      let inverse = 255 - Int(src[offset + 3])
      for channel in 0..<4 {
        let mixed = Int(src[offset + channel]) + Int(dst[offset + channel]) * inverse / 255
        dst[offset + channel] = UInt8(min(255, mixed))
      }
    }
  }

  private func copyImage(_ pixels: UnsafePointer<UInt8>, _ width: Int, _ height: Int) -> CGImage? {
    let data = Data(bytes: pixels, count: width * height * 4) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  private func ensure(width: Int, height: Int) {
    let bytes = width * height * 4
    if layerContext != nil, self.width == width, self.height == height { return }
    if bytes > capacity { destroy(); allocate(bytes) }
    self.width = width
    self.height = height
    guard let layer else { return }
    layerContext = CGContext(
      data: layer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    layerContext?.translateBy(x: 0, y: CGFloat(height))
    layerContext?.scaleBy(x: 1, y: -1)
    layerContext?.setAllowsAntialiasing(true)
    layerContext?.setShouldAntialias(true)
  }

  private func allocate(_ bytes: Int) {
    capacity = bytes
    layer = aligned(bytes)
    temp = aligned(bytes)
    output = aligned(bytes)
  }

  private func aligned(_ bytes: Int) -> UnsafeMutablePointer<UInt8> {
    let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
    let pointer = raw.bindMemory(to: UInt8.self, capacity: bytes)
    pointer.initialize(repeating: 0, count: bytes)
    return pointer
  }

  private func destroy() {
    layerContext = nil
    if let layer { layer.deinitialize(count: capacity); layer.deallocate() }
    if let temp { temp.deinitialize(count: capacity); temp.deallocate() }
    if let output { output.deinitialize(count: capacity); output.deallocate() }
    layer = nil
    temp = nil
    output = nil
    capacity = 0
    width = 0
    height = 0
  }
}

/// Ordered ink, one image per frame. The formula matches the 0.4.5 lattice.
enum PaperInkGrain {
  static func image(
    size: CGSize, time: Double, energy: Double, night: Bool, red: CGFloat, green: CGFloat,
    blue: CGFloat
  ) -> CGImage? {
    SceneGrain.shared.image(
      size: size, time: time, energy: energy, night: night, red: red, green: green, blue: blue)
  }
}

enum PaperAccentGrain {
  static func image(size: CGSize, time: Double, night: Bool) -> CGImage? {
    AccentGrain.shared.image(size: size, time: time, night: night)
  }
}

private final class SceneGrain: @unchecked Sendable {
  static let shared = SceneGrain()
  private let lock = NSLock()
  private var pixels: UnsafeMutablePointer<UInt8>?
  private var capacity = 0
  private var cached: CGImage?
  private var token = ""

  func image(
    size: CGSize, time: Double, energy: Double, night: Bool, red: CGFloat, green: CGFloat,
    blue: CGFloat
  ) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    let longest = max(size.width, size.height)
    guard longest > 1, size.width > 1, size.height > 1 else { return nil }
    let fit = min(1, 1440 / longest)
    let width = max(2, Int((size.width * fit).rounded()))
    let height = max(2, Int((size.height * fit).rounded()))
    let key =
      "\(width)x\(height)|\(Int(time * 30))|\(Int((energy * 100).rounded()))|\(night ? 1 : 0)|\(Int((red * 255).rounded()))|\(Int((green * 255).rounded()))|\(Int((blue * 255).rounded()))"
    if key == token, let cached { return cached }
    ensure(width * height * 4)
    guard let pixels else { return nil }
    ade_scene_grain(
      pixels, Int32(width), Int32(height), Double(size.width), Double(size.height), time, energy,
      Double(red), Double(green), Double(blue), Int32(night ? 1 : 0))
    cached = raster(pixels, width, height)
    token = key
    return cached
  }

  private func ensure(_ bytes: Int) {
    guard bytes > capacity else { return }
    if let pixels { pixels.deinitialize(count: capacity); pixels.deallocate() }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
    pixels = raw.bindMemory(to: UInt8.self, capacity: bytes)
    pixels?.initialize(repeating: 0, count: bytes)
    capacity = bytes
  }
}

private final class AccentGrain: @unchecked Sendable {
  static let shared = AccentGrain()
  private let lock = NSLock()
  private var pixels: UnsafeMutablePointer<UInt8>?
  private var capacity = 0
  private var images: [String: CGImage] = [:]

  func image(size: CGSize, time: Double, night: Bool) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    guard size.width > 1, size.height > 1 else { return nil }
    let longest = max(size.width, size.height) * 2
    let fit = min(1, 720 / longest)
    let width = max(2, Int((size.width * 2 * fit).rounded()))
    let height = max(2, Int((size.height * 2 * fit).rounded()))
    let key = "\(width)x\(height)|\(Int(time * 30))|\(night ? 1 : 0)"
    if let hit = images[key] { return hit }
    if images.count > 16 { images.removeAll() }
    ensure(width * height * 4)
    guard let pixels else { return nil }
    ade_accent_grain(
      pixels, Int32(width), Int32(height), Double(size.width), Double(size.height), time,
      Int32(night ? 1 : 0))
    guard let image = raster(pixels, width, height) else { return nil }
    images[key] = image
    return image
  }

  private func ensure(_ bytes: Int) {
    guard bytes > capacity else { return }
    if let pixels { pixels.deinitialize(count: capacity); pixels.deallocate() }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
    pixels = raw.bindMemory(to: UInt8.self, capacity: bytes)
    pixels?.initialize(repeating: 0, count: bytes)
    capacity = bytes
  }
}

private func raster(_ pixels: UnsafePointer<UInt8>, _ width: Int, _ height: Int) -> CGImage? {
  let data = Data(bytes: pixels, count: width * height * 4) as CFData
  guard let provider = CGDataProvider(data: data) else { return nil }
  return CGImage(
    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}
