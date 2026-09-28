import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let width = CGFloat(pixels)
    NSColor(red: 0.21, green: 0.37, blue: 0.28, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: NSRect(
        x: width * 0.06, y: width * 0.06, width: width * 0.88, height: width * 0.88),
      xRadius: width * 0.2, yRadius: width * 0.2
    ).fill()
    let body = NSBezierPath(
      roundedRect: NSRect(
        x: width * 0.24, y: width * 0.24, width: width * 0.52, height: width * 0.5),
      xRadius: width * 0.06, yRadius: width * 0.06)
    NSColor(red: 0.97, green: 0.96, blue: 0.88, alpha: 1).setFill()
    body.fill()
    NSColor(red: 0.21, green: 0.37, blue: 0.28, alpha: 1).setFill()
    NSBezierPath(
      rect: NSRect(x: width * 0.28, y: width * 0.59, width: width * 0.44, height: width * 0.025)
    ).fill()
    for x in [0.36, 0.59] {
      NSBezierPath(
        roundedRect: NSRect(
          x: width * x, y: width * 0.69, width: width * 0.05, height: width * 0.12),
        xRadius: width * 0.022, yRadius: width * 0.022
      ).fill()
    }
    for x in [0.35, 0.49, 0.63] {
      for y in [0.37, 0.49] {
        NSBezierPath(
          ovalIn: NSRect(
            x: width * x - width * 0.025, y: width * y - width * 0.025, width: width * 0.05,
            height: width * 0.05)
        ).fill()
      }
    }
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(size)x\(size)\(scale==2 ? "@2x":"").png"
    try rep.representation(using: .png, properties: [:])!.write(
      to: output.appendingPathComponent(name))
  }
}

// ICNS stores modern PNG representations directly; this also works with CLT-only installations.
if CommandLine.arguments.count > 2 {
  func be32(_ value: Int) -> Data {
    var big = UInt32(value).bigEndian
    return withUnsafeBytes(of: &big) { Data($0) }
  }
  var chunks = Data()
  for (type, name) in [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
  ] {
    let png = try Data(contentsOf: output.appendingPathComponent(name))
    chunks.append(Data(type.utf8))
    chunks.append(be32(png.count + 8))
    chunks.append(png)
  }
  var icns = Data("icns".utf8)
  icns.append(be32(chunks.count + 8))
  icns.append(chunks)
  try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
