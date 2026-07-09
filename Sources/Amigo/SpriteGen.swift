import AppKit
import ImageIO

/// 5 个默认动作。prompt 强调"同尺寸/居中/双脚同一基线"，配合帧对齐消除跳动。
enum PetAnimAction: String, CaseIterable, Identifiable {
    case work, phone, think, idle, run, walk
    var id: String { rawValue }
    var title: String {
        switch self { case .work: "工作"; case .phone: "打电话"; case .think: "思考"; case .idle: "待着"; case .run: "跑动"; case .walk: "走路" }
    }
    var emoji: String {
        switch self { case .work: "💻"; case .phone: "📞"; case .think: "🤔"; case .idle: "🧍"; case .run: "🏃"; case .walk: "🚶" }
    }
    var fps: Double {   // 16 帧：适中播放速度，别太快（idle 最慢、run 最快）
        switch self { case .work: 8; case .phone: 8; case .think: 6; case .idle: 5; case .run: 13; case .walk: 10 }
    }
    private var motion: String {
        switch self {
        case .work:
            return "The character is sitting at a small computer desk seen from the front, typing on a laptop. Frame1: hands resting on keyboard, neutral. Frame2: fingers pressing keys, tiny head tilt. Frame3: typing, small shoulder rise (a breath). Frame4: back to neutral. A subtle looping typing motion."
        case .phone:
            return "The character is holding a phone to their ear with one hand, talking, seen from the front. Frame1: phone at ear, mouth slightly open. Frame2: free hand makes a small gesture. Frame3: a slight nod. Frame4: neutral. A subtle looping talking motion."
        case .think:
            return "The character is in a thinking pose seen from the front, one hand near the chin, eyes looking up thoughtfully. Frame1: hand at chin. Frame2: slight head tilt. Frame3: eyes glance further up. Frame4: neutral. A subtle looping thinking motion."
        case .idle:
            return "The character stands still and relaxed, front view — a VERY SUBTLE idle loop. Frame1: neutral. Frame2: eyes blink (closed) with a tiny arm sway. Frame3: gentle breath, slight weight shift onto one foot, the other foot scuffs a little. Frame4: settle back to neutral. Keep the motion calm and minimal."
        case .run:
            return "The character is running to the right in side profile — a 4-frame run cycle. Frame1: right leg forward, left leg back, arms swinging. Frame2: legs passing under the body. Frame3: left leg forward, right leg back, arms swinging opposite. Frame4: legs passing again. All frames show the SAME right-facing side profile."
        case .walk:
            return "The character is walking to the right in side profile — a calm, relaxed 4-frame walk cycle (slower and gentler than a run). Frame1: right leg forward, left leg back, arms gently swinging. Frame2: legs passing under the body. Frame3: left leg forward, right leg back. Frame4: legs passing again. All frames show the SAME right-facing side profile with an even, unhurried stride."
        }
    }
    var prompt: String {
        motion + "\n\nRender this as a SMOOTH 16-frame animation loop arranged in a 4x4 grid (read left-to-right, top-to-bottom) on a plain solid white background. "
        + "The key poses described above are the main beats — interpolate gentle in-between frames so the 16 frames play back as one fluid, seamless loop (frame 16 flows naturally back into frame 1). "
        + "Detailed 32-bit pixel art, the EXACT same character design, colors and size in every one of the 16 cells. "
        + "CRITICAL FOR ANIMATION: the character must be horizontally centered with feet resting on the SAME horizontal ground line in every cell, so all 16 frames line up perfectly when looped. "
        + "Do NOT draw any text, letters, numbers, labels, watermarks, grid lines, borders or frame dividers."
    }
}

enum SpriteGenError: LocalizedError {
    case noReference, decode
    var errorDescription: String? {
        switch self {
        case .noReference: return "当前形象没有可用作参考的图片（先在宠物页选一个鱼 / 做个自定义形象）"
        case .decode: return "无法解析生成的图片"
        }
    }
}

enum SpriteGen {
    static var root: URL { PetImages.dir.appendingPathComponent("generated", isDirectory: true) }
    /// 动画按形象绑定：generated/<形象>/<动作>/
    static func dir(character: String, action: String) -> URL {
        root.appendingPathComponent(character, isDirectory: true).appendingPathComponent(action, isDirectory: true)
    }

    /// 生成某动作（绑定到当前形象）：直连生图 → 2×2 切 4 帧 → 去白底 + 底部居中对齐
    static func generate(actionId: String, prompt: String, character: String, referencePNG: Data, baseUrl: String, apiKey: String) async throws -> Int {
        let data = try await ImageGen.edit(baseUrl: baseUrl, apiKey: apiKey, prompt: prompt, references: [referencePNG])
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw SpriteGenError.decode }
        return try sliceRegisterSave(sheet, character: character, action: actionId)
    }

    /// 一次性迁移：把旧的扁平 generated/<action>/ 归到 generated/<character>/<action>/
    static func migrateFlat(to character: String) {
        let fm = FileManager.default
        for a in PetAnimAction.allCases {
            let flat = root.appendingPathComponent(a.rawValue, isDirectory: true)
            guard fm.fileExists(atPath: flat.appendingPathComponent("frame-0.png").path) else { continue }
            let dest = dir(character: character, action: a.rawValue)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: dest.path) { try? fm.moveItem(at: flat, to: dest) }
        }
    }

    static let gridCols = 4, gridRows = 4, frameCount = 16   // 4×4 = 16 帧，动画更连贯

    private static func sliceRegisterSave(_ sheet: CGImage, character: String, action: String) throws -> Int {
        let cw = sheet.width / gridCols, ch = sheet.height / gridRows
        var rects: [CGRect] = []
        for r in 0..<gridRows { for c in 0..<gridCols {   // 从左到右、从上到下读
            rects.append(CGRect(x: c * cw, y: r * ch, width: cw, height: ch))
        } }
        let cells = rects.compactMap { sheet.cropping(to: $0) }
        guard cells.count == frameCount else { throw SpriteGenError.decode }

        let registered = register(cells.map { removeWhite($0) ?? $0 })

        let d = dir(character: character, action: action)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        for i in 0..<64 { try? FileManager.default.removeItem(at: d.appendingPathComponent("frame-\(i).png")) }
        var n = 0
        for (i, img) in registered.enumerated() {
            guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { continue }
            try png.write(to: d.appendingPathComponent("frame-\(i).png")); n += 1
        }
        guard n == frameCount else { throw SpriteGenError.decode }
        return n
    }

    // MARK: 对齐：底部对齐(双脚定住) + 水平以「重心」为锚(身体不横晃)
    private static func register(_ frames: [CGImage]) -> [CGImage] {
        var recs: [(img: CGImage, box: CGRect, cx: CGFloat)] = []
        for f in frames {
            guard let box = alphaBBox(f), let cx = centroidX(f, box: box) else { return frames }
            recs.append((f, box, cx))
        }
        let maxH = recs.map { $0.box.height }.max() ?? 0
        // 以每帧水平重心为锚点(比包围盒中心稳)，锚点两侧各留最大伸展 → 播放不横晃
        let left = recs.map { $0.cx - $0.box.minX }.max() ?? 0
        let right = recs.map { $0.box.maxX - $0.cx }.max() ?? 0
        let cvW = Int(((left + right) * 1.06 + 6).rounded())
        let cvH = Int((maxH * 1.12).rounded())
        guard cvW > 0, cvH > 0 else { return frames }
        let anchorX = left + 3
        var out: [CGImage] = []
        for r in recs {
            guard let crop = r.img.cropping(to: r.box), let c = ctx(cvW, cvH) else { out.append(r.img); continue }
            c.clear(CGRect(x: 0, y: 0, width: cvW, height: cvH))
            let x = anchorX - (r.cx - r.box.minX)   // 重心对齐到画布同一 x
            // 底部对齐：y=0 是画布底（CGContext 原点在左下），双脚落到底线
            c.draw(crop, in: CGRect(x: x, y: 0, width: r.box.width, height: r.box.height))
            out.append(c.makeImage() ?? r.img)
        }
        return out
    }

    /// 非透明像素的水平重心（胳膊/头摆动不带偏整体，避免横晃）
    private static func centroidX(_ img: CGImage, box: CGRect) -> CGFloat? {
        let w = img.width, h = img.height
        guard let c = ctx(w, h), let buf = { () -> UnsafeMutableRawPointer? in
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return c.data
        }() else { return nil }
        let px = buf.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let x0 = max(0, Int(box.minX)), x1 = min(w, Int(box.maxX))
        let y0 = max(0, Int(box.minY)), y1 = min(h, Int(box.maxY))
        guard x1 > x0, y1 > y0 else { return box.midX }
        var sumX = 0.0, cnt = 0.0
        for y in y0..<y1 {
            let row = y * w
            for x in x0..<x1 where px[(row + x) * 4 + 3] > 16 { sumX += Double(x); cnt += 1 }
        }
        return cnt < 1 ? box.midX : CGFloat(sumX / cnt)
    }

    /// 非透明像素的包围盒（top-left 原点，供 cropping 使用）
    private static func alphaBBox(_ img: CGImage) -> CGRect? {
        let w = img.width, h = img.height
        guard let c = ctx(w, h), let buf = { () -> UnsafeMutableRawPointer? in
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return c.data
        }() else { return nil }
        let px = buf.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where px[(row + x) * 4 + 3] > 16 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// 四边 flood-fill 去白底（只去与边相连的白，保留内部白）
    private static func removeWhite(_ img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        guard let c = ctx(w, h), let buf = { () -> UnsafeMutableRawPointer? in
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return c.data
        }() else { return nil }
        let px = buf.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var seen = [Bool](repeating: false, count: w * h)
        var st = [Int]()
        func white(_ i: Int) -> Bool { let o = i*4; return px[o] > 224 && px[o+1] > 224 && px[o+2] > 224 }
        for x in 0..<w { st.append(x); st.append((h-1)*w + x) }
        for y in 0..<h { st.append(y*w); st.append(y*w + w-1) }
        while let i = st.popLast() {
            if seen[i] { continue }; seen[i] = true
            if !white(i) { continue }
            let o = i*4; px[o]=0; px[o+1]=0; px[o+2]=0; px[o+3]=0
            let x = i % w, y = i / w
            if x+1 < w { st.append(i+1) }; if x > 0 { st.append(i-1) }
            if y+1 < h { st.append(i+w) }; if y > 0 { st.append(i-w) }
        }
        // 去白边：把仍贴着透明、且接近白/浅灰的边缘像素也抹掉（消除运动时漏白）；内部白不挨透明，保住
        for _ in 0..<2 {
            var kill = [Int]()
            for i in 0..<(w * h) {
                let o = i * 4
                if px[o+3] == 0 { continue }
                guard min(px[o], px[o+1], px[o+2]) > 180 else { continue }   // 只处理接近白/浅灰
                let x = i % w, y = i / w
                let edge = (x+1 < w && px[(i+1)*4+3] == 0) || (x > 0 && px[(i-1)*4+3] == 0)
                    || (y+1 < h && px[(i+w)*4+3] == 0) || (y > 0 && px[(i-w)*4+3] == 0)
                if edge { kill.append(o) }
            }
            if kill.isEmpty { break }
            for o in kill { px[o] = 0; px[o+1] = 0; px[o+2] = 0; px[o+3] = 0 }
        }
        return c.makeImage()
    }

    private static func ctx(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func exists(character: String, action: String) -> Bool {
        FileManager.default.fileExists(atPath: dir(character: character, action: action).appendingPathComponent("frame-0.png").path)
    }

    /// 读某形象某动作已生成的帧
    static func loadFrames(character: String, action: String) -> [NSImage] {
        var imgs: [NSImage] = []
        for i in 0..<64 {   // 读到缺帧为止，兼容旧的 4 帧与新的 16 帧
            let u = dir(character: character, action: action).appendingPathComponent("frame-\(i).png")
            guard FileManager.default.fileExists(atPath: u.path), let img = NSImage(contentsOf: u) else { break }
            imgs.append(img)
        }
        return imgs
    }
}
