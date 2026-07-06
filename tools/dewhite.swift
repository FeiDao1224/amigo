import AppKit

// 白底角色图 → 透明 PNG。从四边 flood-fill 只删和边缘连通的近白背景，
// 保留角色内部的白色（眼睛、牙齿、衣服）。
// 用法: swift tools/dewhite.swift <in.png> <out.png> [threshold=245] [tolerance=18]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: swift dewhite.swift <in.png> <out.png> [threshold] [tolerance]\n".data(using: .utf8)!)
    exit(1)
}
let inPath = args[1], outPath = args[2]
let threshold = args.count > 3 ? (Int(args[3]) ?? 245) : 245
let tolerance = args.count > 4 ? (Int(args[4]) ?? 18) : 18
let bgMin = threshold - tolerance

guard let img = NSImage(contentsOfFile: inPath),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot load \(inPath)\n".data(using: .utf8)!); exit(1)
}
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

func isBg(_ p: Int) -> Bool {
    let i = p * 4
    if px[i + 3] < 8 { return false }
    return Int(px[i]) >= bgMin && Int(px[i + 1]) >= bgMin && Int(px[i + 2]) >= bgMin
}

var visited = [Bool](repeating: false, count: w * h)
var stack = [Int]()
stack.reserveCapacity(w * h / 4)
for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }

var removed = 0
while let p = stack.popLast() {
    if visited[p] { continue }
    visited[p] = true
    if !isBg(p) { continue }
    let i = p * 4
    px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0   // 全 0 避免白边
    removed += 1
    let x = p % w, y = p / w
    if x > 0 { stack.append(p - 1) }
    if x < w - 1 { stack.append(p + 1) }
    if y > 0 { stack.append(p - w) }
    if y < h - 1 { stack.append(p + w) }
}

guard let out = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: out)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? FileManager.default.createDirectory(at: URL(fileURLWithPath: outPath).deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
do { try data.write(to: URL(fileURLWithPath: outPath))
     print("ok: \(outPath)  (\(w)x\(h), 去除 \(removed) 像素)") }
catch { FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!); exit(1) }
