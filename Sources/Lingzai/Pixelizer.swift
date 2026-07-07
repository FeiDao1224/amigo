import AppKit
import CoreGraphics

/// 通用像素化器：任意图 → 像素风（自适应 posterize 调色板，非某角色专属）
/// 供"自定义形象"用：用户选图 → 像素化 → 存成桌宠。
enum Pixelizer {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static func ctx(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// 返回像素化后的 NSImage（用于预览）
    static func pixelize(_ image: NSImage, rows: Int = 88, levels: Int = 5, scale: Int = 3, flood: Bool = false) -> NSImage? {
        guard let src = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cg = core(src, rows: rows, levels: levels, scale: scale, flood: flood) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// 像素化并写成 PNG（用于落盘成桌宠）
    @discardableResult
    static func writePNG(_ image: NSImage, to url: URL, rows: Int, levels: Int, scale: Int, flood: Bool) -> Bool {
        guard let src = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cg = core(src, rows: rows, levels: levels, scale: scale, flood: flood),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return true
        } catch { return false }
    }

    private static func core(_ src: CGImage, rows: Int, levels: Int, scale: Int, flood: Bool) -> CGImage? {
        // 1) 缩小到低分辨率（区域平均 → 干净像素块）
        let lowH = max(1, rows)
        let lowW = max(1, Int((Double(src.width) * Double(rows) / Double(src.height)).rounded()))
        guard let low = ctx(lowW, lowH), let buf = low.data else { return nil }
        low.interpolationQuality = .medium
        low.clear(CGRect(x: 0, y: 0, width: lowW, height: lowH))
        low.draw(src, in: CGRect(x: 0, y: 0, width: lowW, height: lowH))

        let px = buf.bindMemory(to: UInt8.self, capacity: lowW * lowH * 4)
        let stepN = Double(max(2, levels) - 1)
        func post(_ v: Double) -> UInt8 { UInt8(((v / 255.0 * stepN).rounded() / stepN * 255.0).rounded()) }

        // 2) 可选：四边 flood-fill 去白底
        if flood {
            var seen = [Bool](repeating: false, count: lowW * lowH)
            var q = [(Int, Int)]()
            func isBg(_ x: Int, _ y: Int) -> Bool {
                let i = (y * lowW + x) * 4
                if px[i+3] == 0 { return true }
                return px[i] > 210 && px[i+1] > 210 && px[i+2] > 210
            }
            for x in 0..<lowW { q.append((x, 0)); q.append((x, lowH-1)) }
            for y in 0..<lowH { q.append((0, y)); q.append((lowW-1, y)) }
            while let (x, y) = q.popLast() {
                if x < 0 || y < 0 || x >= lowW || y >= lowH { continue }
                let idx = y * lowW + x; if seen[idx] { continue }; seen[idx] = true
                if !isBg(x, y) { continue }
                let i = idx * 4; px[i] = 0; px[i+1] = 0; px[i+2] = 0; px[i+3] = 0
                q.append((x+1, y)); q.append((x-1, y)); q.append((x, y+1)); q.append((x, y-1))
            }
        }

        // 3) 硬化 alpha + 反预乘还原真色 + posterize
        for i in stride(from: 0, to: lowW * lowH * 4, by: 4) {
            let al = px[i+3]
            if al < 128 { px[i] = 0; px[i+1] = 0; px[i+2] = 0; px[i+3] = 0; continue }
            let inv = 255.0 / Double(al)
            px[i]   = post(min(255, Double(px[i])   * inv))
            px[i+1] = post(min(255, Double(px[i+1]) * inv))
            px[i+2] = post(min(255, Double(px[i+2]) * inv))
            px[i+3] = 255
        }

        // 4) 最近邻放大 → 硬边像素块烤进图
        guard let lowImg = low.makeImage() else { return nil }
        let outW = lowW * max(1, scale), outH = lowH * max(1, scale)
        guard let out = ctx(outW, outH) else { return nil }
        out.interpolationQuality = .none
        out.draw(lowImg, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return out.makeImage()
    }
}
