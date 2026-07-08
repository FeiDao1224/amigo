import AppKit
import CoreGraphics
let fishPath = NSString(string: "~/Library/Application Support/Lingzai/pets/anxious_fish.png").expandingTildeInPath
guard let fish = NSImage(contentsOfFile: fishPath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("no fish png"); exit(1) }
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func ctx(_ s: Int) -> CGContext { CGContext(data:nil,width:s,height:s,bitsPerComponent:8,bytesPerRow:0,space:sRGB,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)! }
func renderIcon(_ size: Int) -> CGImage {
    let c = ctx(size); let S = CGFloat(size)
    let inset = S * 0.086
    let rect = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
    let radius = rect.width * 0.2237
    c.saveGState()
    c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); c.clip()
    let grad = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(red:0.60,green:0.88,blue:0.82,alpha:1), CGColor(red:0.22,green:0.60,blue:0.72,alpha:1)] as CFArray, locations: [0,1])!
    c.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // 顶部柔光
    let hl = CGGradient(colorsSpace: sRGB, colors: [CGColor(red:1,green:1,blue:1,alpha:0.22), CGColor(red:1,green:1,blue:1,alpha:0)] as CFArray, locations:[0,1])!
    c.drawLinearGradient(hl, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    c.restoreGState()
    let fw = CGFloat(fish.width), fh = CGFloat(fish.height)
    let scale = (rect.height * 0.64) / fh
    let dw = fw*scale, dh = fh*scale
    c.setShadow(offset: CGSize(width: 0, height: -S*0.012), blur: S*0.022, color: CGColor(red:0,green:0,blue:0,alpha:0.28))
    c.draw(fish, in: CGRect(x: rect.midX - dw/2, y: rect.midY - dh/2 + S*0.01, width: dw, height: dh))
    return c.makeImage()!
}
func save(_ img: CGImage,_ path:String){ try! NSBitmapImageRep(cgImage:img).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path)) }
let out = "AppIcon.iconset"; try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
save(renderIcon(1024), "/tmp/icon_preview.png")
for (name,px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    save(renderIcon(px), "\(out)/icon_\(name).png")
}
print("iconset 生成完成")
