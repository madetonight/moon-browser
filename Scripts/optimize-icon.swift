import AppKit
import Foundation
import ImageIO

// Native ICNS supports JPEG 2000 payloads for its larger representations.
// Keep small PNG representations exact; compress the high-resolution artwork
// at high quality without changing its source, crop, palette or icon geometry.
guard CommandLine.arguments.count == 2 else { fatalError("Pass an ICNS path") }
let file = URL(fileURLWithPath: CommandLine.arguments[1])
let original = try Data(contentsOf: file)
func number(_ data: Data, at index: Int) -> Int {
    Int(data[index]) << 24 | Int(data[index + 1]) << 16 | Int(data[index + 2]) << 8 | Int(data[index + 3])
}
func bytes(_ value: Int) -> Data {
    Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
}
guard original.count >= 8, original.prefix(4) == Data("icns".utf8),
      number(original, at: 4) == original.count else { fatalError("Invalid ICNS header") }
let supported = Set(["ic07", "ic08", "ic09", "ic10", "ic13", "ic14"])
var chunks: [(Data, Data)] = []
var offset = 8
var hadContents = false
while offset < original.count {
    guard offset + 8 <= original.count else { fatalError("Truncated ICNS chunk") }
    let type = original.subdata(in: offset..<(offset + 4))
    let size = number(original, at: offset + 4)
    guard size >= 8, size <= original.count - offset else { fatalError("Invalid ICNS chunk length") }
    var payload = original.subdata(in: (offset + 8)..<(offset + size))
    offset += size
    let name = String(data: type, encoding: .ascii) ?? ""
    if name == "TOC " { hadContents = true; continue }
    if supported.contains(name),
       let source = CGImageSourceCreateWithData(payload as CFData, nil),
       let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
        let encoded = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg-2000" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image,
                                      [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
            if CGImageDestinationFinalize(destination), encoded.length < payload.count {
                payload = encoded as Data
            }
        }
    }
    chunks.append((type, payload))
}
var body = Data()
if hadContents {
    var contents = Data()
    for (type, payload) in chunks { contents.append(type); contents.append(bytes(payload.count + 8)) }
    body.append(Data("TOC ".utf8)); body.append(bytes(contents.count + 8)); body.append(contents)
}
for (type, payload) in chunks {
    body.append(type); body.append(bytes(payload.count + 8)); body.append(payload)
}
var result = Data("icns".utf8)
result.append(bytes(body.count + 8)); result.append(body)
guard NSImage(data: result) != nil else { fatalError("Optimized icon cannot be decoded") }
if result.count < original.count {
    try result.write(to: file, options: .atomic)
    print("Native icon: \(original.count) → \(result.count) bytes")
}
