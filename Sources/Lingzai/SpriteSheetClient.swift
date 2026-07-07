import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 最小生成客户端：调本地 sprite-sheet-creator（localhost:3000）出 idle sprite sheet，
/// 切成 4 帧写入 Application Support/Lingzai/pets/generated/idle/。
/// 密钥全在 web 服务端 .env，App 侧不接触任何 key。
enum SpriteSheetError: LocalizedError {
    case noReference, network(String), http(Int, String), decode
    var errorDescription: String? {
        switch self {
        case .noReference: return "当前形象没有可用作参考的图片（先在宠物页选一个鱼 / 做个自定义形象）"
        case .network(let s): return "连不上本地生成服务 localhost:3000（先启动 sprite-sheet-creator）：\(s)"
        case .http(let c, let m): return "生成服务返回 \(c)：\(m)"
        case .decode: return "无法解析返回的图片"
        }
    }
}

enum SpriteSheetClient {
    static let endpoint = URL(string: "http://localhost:3000/api/generate-sprite-sheet")!

    /// 生成 idle sprite sheet 并切 4 帧，返回帧数（应为 4）
    static func generateIdle(referencePNG: Data) async throws -> Int {
        let dataURL = "data:image/png;base64," + referencePNG.base64EncodedString()
        let body: [String: Any] = [
            "characterImageUrl": dataURL,
            "type": "idle",
            "imageModel": "gpt-image-2",
            "gptImageQuality": "medium",
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 180   // 生图较慢

        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw SpriteSheetError.network(error.localizedDescription) }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let msg = (json?["error"] as? String) ?? String(data: data, encoding: .utf8)?.prefix(200).description ?? "未知错误"
            throw SpriteSheetError.http(code, msg)
        }
        guard let imageUrl = json?["imageUrl"] as? String else { throw SpriteSheetError.decode }

        let sheetData = try await resolveImage(imageUrl)
        guard let src = CGImageSourceCreateWithData(sheetData as CFData, nil),
              let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw SpriteSheetError.decode }
        return try sliceAndSave(sheet)
    }

    /// 返回图片字节：支持 data:image/...;base64 或普通 http(s) URL
    private static func resolveImage(_ s: String) async throws -> Data {
        if s.hasPrefix("data:") {
            guard let comma = s.firstIndex(of: ","),
                  let d = Data(base64Encoded: String(s[s.index(after: comma)...])) else { throw SpriteSheetError.decode }
            return d
        }
        guard let url = URL(string: s) else { throw SpriteSheetError.decode }
        do { return try await URLSession.shared.data(from: url).0 }
        catch { throw SpriteSheetError.network(error.localizedDescription) }
    }

    static var generatedIdleDir: URL {
        PetImages.dir.appendingPathComponent("generated/idle", isDirectory: true)
    }

    /// 2×2 → 4 帧（左上/右上/左下/右下），去白底后写 frame-0..3.png
    private static func sliceAndSave(_ sheet: CGImage) throws -> Int {
        let dir = generatedIdleDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 清掉旧帧
        for i in 0..<8 { try? FileManager.default.removeItem(at: dir.appendingPathComponent("frame-\(i).png")) }

        let cw = sheet.width / 2, ch = sheet.height / 2
        let cells = [CGRect(x: 0, y: 0, width: cw, height: ch),      // 帧1 左上
                     CGRect(x: cw, y: 0, width: cw, height: ch),     // 帧2 右上
                     CGRect(x: 0, y: ch, width: cw, height: ch),     // 帧3 左下
                     CGRect(x: cw, y: ch, width: cw, height: ch)]    // 帧4 右下
        var n = 0
        for (i, r) in cells.enumerated() {
            guard let cell = sheet.cropping(to: r) else { continue }
            let clean = removeWhite(cell) ?? cell
            guard let png = NSBitmapImageRep(cgImage: clean).representation(using: .png, properties: [:]) else { continue }
            try png.write(to: dir.appendingPathComponent("frame-\(i).png"))
            n += 1
        }
        guard n == 4 else { throw SpriteSheetError.decode }
        return n
    }

    /// 从四边 flood-fill 去白底（与现有 dewhite 一致：只去与边相连的白，保留内部白）
    private static func removeWhite(_ img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buf = { () -> UnsafeMutableRawPointer? in
                  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return ctx.data
              }() else { return nil }
        let px = buf.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var seen = [Bool](repeating: false, count: w * h)
        var stack = [Int]()
        func isWhite(_ i: Int) -> Bool { let o = i*4; return px[o] > 224 && px[o+1] > 224 && px[o+2] > 224 }
        for x in 0..<w { stack.append(x); stack.append((h-1)*w + x) }
        for y in 0..<h { stack.append(y*w); stack.append(y*w + w-1) }
        while let i = stack.popLast() {
            if seen[i] { continue }; seen[i] = true
            if !isWhite(i) { continue }
            let o = i*4; px[o]=0; px[o+1]=0; px[o+2]=0; px[o+3]=0
            let x = i % w, y = i / w
            if x+1 < w { stack.append(i+1) }
            if x > 0 { stack.append(i-1) }
            if y+1 < h { stack.append(i+w) }
            if y > 0 { stack.append(i-w) }
        }
        return ctx.makeImage()
    }
}
