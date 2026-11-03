import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let artwork = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("MoonIconArtwork.png")
guard let source = NSImage(contentsOf: artwork) else {
    fatalError("Missing Moon icon artwork: \(artwork.path)")
}
// Sample the gradient tile inside the artwork's presentation margins. The
// native icon mask supplies clean, transparent corners at every size.
// The selected Pearl Current artwork includes a presentation margin. Retain the
// tile's thin glass edge; NSImage source coordinates start at the lower-left.
let sourceRect = NSRect(x: source.size.width * 0.10,
                        y: source.size.height * 0.11,
                        width: source.size.width * 0.80,
                        height: source.size.height * 0.80)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(size) / 1024
    let bounds = NSRect(x: 58 * scale, y: 58 * scale, width: 908 * scale, height: 908 * scale)
    let tile = NSBezierPath(roundedRect: bounds, xRadius: 210 * scale, yRadius: 210 * scale)
    tile.addClip()
    NSColor.white.setFill()
    tile.fill()
    source.draw(in: bounds, from: sourceRect, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    if size <= 512 { try png.write(to: destination.appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { try png.write(to: destination.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png")) }
}
