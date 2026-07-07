import AppKit
import CoreGraphics
import Vision
import CoreImage

/// 通用像素化器：任意图 → 像素风。cutout=true 时先用 Vision 自动抠主体（任意背景都能去），
/// 抠图失败/系统过旧再退回"四边白底 flood"，最后统一去边缘浅色残留。全部本机完成。
enum Pixelizer {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static func ctx(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func pixelize(_ image: NSImage, rows: Int = 88, levels: Int = 5, scale: Int = 3, cutout: Bool = true) -> NSImage? {
        guard let cg = render(image, rows: rows, levels: levels, scale: scale, cutout: cutout) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    @discardableResult
    static func writePNG(_ image: NSImage, to url: URL, rows: Int, levels: Int, scale: Int, cutout: Bool) -> Bool {
        guard let cg = render(image, rows: rows, levels: levels, scale: scale, cutout: cutout),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url); return true
        } catch { return false }
    }

    private static func render(_ image: NSImage, rows: Int, levels: Int, scale: Int, cutout: Bool) -> CGImage? {
        guard var src = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var didCut = false
        if cutout, let masked = subjectCutout(src) { src = masked; didCut = true }
        return core(src, rows: rows, levels: levels, scale: scale, floodWhite: cutout && !didCut)
    }

    /// Vision 自动抠主体（macOS 14+）：返回背景透明的图；失败/系统旧返回 nil
    static func subjectCutout(_ cg: CGImage) -> CGImage? {
        guard #available(macOS 14.0, *) else { return nil }
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([req])) != nil,
              let res = req.results?.first,
              let pb = try? res.generateMaskedImage(ofInstances: res.allInstances, from: handler, croppedToInstancesExtent: false)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: pb)
        return CIContext(options: nil).createCGImage(ci, from: ci.extent)
    }

    private static func core(_ src: CGImage, rows: Int, levels: Int, scale: Int, floodWhite: Bool) -> CGImage? {
        let lowH = max(1, rows)
        let lowW = max(1, Int((Double(src.width) * Double(rows) / Double(src.height)).rounded()))
        guard let low = ctx(lowW, lowH), let buf = low.data else { return nil }
        low.interpolationQuality = .medium
        low.clear(CGRect(x: 0, y: 0, width: lowW, height: lowH))
        low.draw(src, in: CGRect(x: 0, y: 0, width: lowW, height: lowH))

        let px = buf.bindMemory(to: UInt8.self, capacity: lowW * lowH * 4)
        let stepN = Double(max(2, levels) - 1)
        func post(_ v: Double) -> UInt8 { UInt8(((v / 255.0 * stepN).rounded() / stepN * 255.0).rounded()) }

        // 白底图兜底：四边 flood-fill 去白（Vision 抠图成功时不需要）
        if floodWhite {
            var seen = [Bool](repeating: false, count: lowW * lowH); var q = [Int]()
            func isBg(_ i: Int) -> Bool { let o = i*4; return px[o+3] == 0 || (px[o] > 208 && px[o+1] > 208 && px[o+2] > 208) }
            for x in 0..<lowW { q.append(x); q.append((lowH-1)*lowW + x) }
            for y in 0..<lowH { q.append(y*lowW); q.append(y*lowW + lowW-1) }
            while let i = q.popLast() {
                if seen[i] { continue }; seen[i] = true
                if !isBg(i) { continue }
                let o = i*4; px[o]=0; px[o+1]=0; px[o+2]=0; px[o+3]=0
                let x = i % lowW, y = i / lowW
                if x+1 < lowW { q.append(i+1) }; if x > 0 { q.append(i-1) }
                if y+1 < lowH { q.append(i+lowW) }; if y > 0 { q.append(i-lowW) }
            }
        }

        // 硬化 alpha + 反预乘还原真色 + posterize
        for i in stride(from: 0, to: lowW*lowH*4, by: 4) {
            let al = px[i+3]
            if al < 110 { px[i]=0; px[i+1]=0; px[i+2]=0; px[i+3]=0; continue }
            let inv = 255.0 / Double(al)
            px[i]   = post(min(255, Double(px[i])   * inv))
            px[i+1] = post(min(255, Double(px[i+1]) * inv))
            px[i+2] = post(min(255, Double(px[i+2]) * inv))
            px[i+3] = 255
        }

        // 去边缘浅色残留（贴透明、且接近白/浅灰）→ 消除运动时漏白
        for _ in 0..<2 {
            var kill = [Int]()
            for i in 0..<(lowW * lowH) {
                let o = i*4; if px[o+3] == 0 { continue }
                guard min(px[o], px[o+1], px[o+2]) > 185 else { continue }
                let x = i % lowW, y = i / lowW
                let edge = (x+1 < lowW && px[(i+1)*4+3] == 0) || (x > 0 && px[(i-1)*4+3] == 0)
                    || (y+1 < lowH && px[(i+lowW)*4+3] == 0) || (y > 0 && px[(i-lowW)*4+3] == 0)
                if edge { kill.append(o) }
            }
            if kill.isEmpty { break }
            for o in kill { px[o]=0; px[o+1]=0; px[o+2]=0; px[o+3]=0 }
        }

        // 最近邻放大 → 硬边像素块烤进图
        guard let lowImg = low.makeImage() else { return nil }
        let outW = lowW * max(1, scale), outH = lowH * max(1, scale)
        guard let out = ctx(outW, outH) else { return nil }
        out.interpolationQuality = .none
        out.draw(lowImg, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return out.makeImage()
    }
}
