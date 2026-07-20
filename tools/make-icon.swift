// 重新生成 App 图标：把某个内置形象放进圆角渐变底，导出成 AppIcon.iconset。
//
//   swift tools/make-icon.swift [形象名]        # 默认 penguin，取 Assets/pets/<形象名>.png
//   iconutil -c icns AppIcon.iconset -o AppIcon.icns
//
// 只在需要换图标时手动跑，不是构建流程的一部分。
import AppKit
import CoreGraphics

let character = CommandLine.arguments.dropFirst().first ?? "penguin"
let source = "Assets/pets/\(character).png"
guard let pet = NSImage(contentsOfFile: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("读不到 \(source)（请在仓库根目录运行）\n".utf8))
    exit(1)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func ctx(_ s: Int) -> CGContext {
    CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
              space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func renderIcon(_ size: Int) -> CGImage {
    let c = ctx(size), S = CGFloat(size)
    let inset = S * 0.086
    let rect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let radius = rect.width * 0.2237          // macOS 圆角矩形比例
    c.saveGState()
    c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); c.clip()
    let grad = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(red: 0.60, green: 0.88, blue: 0.82, alpha: 1),
        CGColor(red: 0.22, green: 0.60, blue: 0.72, alpha: 1)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // 顶部柔光
    let hl = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(hl, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    c.restoreGState()

    let scale = (rect.height * 0.64) / CGFloat(pet.height)
    let dw = CGFloat(pet.width) * scale, dh = CGFloat(pet.height) * scale
    c.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.022,
                color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    c.draw(pet, in: CGRect(x: rect.midX - dw / 2, y: rect.midY - dh / 2 + S * 0.01, width: dw, height: dh))
    return c.makeImage()!
}

func save(_ img: CGImage, to path: String) {
    guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let out = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    save(renderIcon(px), to: "\(out)/icon_\(name).png")
}
print("已生成 \(out)/（形象：\(character)）— 接着跑：iconutil -c icns \(out) -o AppIcon.icns")
