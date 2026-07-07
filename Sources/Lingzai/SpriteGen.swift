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
    var fps: Double {
        switch self { case .work: 4; case .phone: 4; case .think: 3; case .idle: 3; case .run: 8; case .walk: 5 }
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
        motion + "\n\nArrange the 4 frames in a 2x2 grid on a plain solid white background. Detailed 32-bit pixel art, exact same character design in every frame. "
        + "CRITICAL FOR ANIMATION: the character must be the SAME size and horizontally centered in every frame, with the feet resting on the SAME horizontal ground line, so the four frames line up perfectly when looped. "
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
    static func generate(action: PetAnimAction, character: String, referencePNG: Data, baseUrl: String, apiKey: String) async throws -> Int {
        let data = try await ImageGen.edit(baseUrl: baseUrl, apiKey: apiKey, prompt: action.prompt, referencePNG: referencePNG)
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw SpriteGenError.decode }
        return try sliceRegisterSave(sheet, character: character, action: action.rawValue)
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

    private static func sliceRegisterSave(_ sheet: CGImage, character: String, action: String) throws -> Int {
        let cw = sheet.width / 2, ch = sheet.height / 2
        let rects = [CGRect(x: 0, y: 0, width: cw, height: ch), CGRect(x: cw, y: 0, width: cw, height: ch),
                     CGRect(x: 0, y: ch, width: cw, height: ch), CGRect(x: cw, y: ch, width: cw, height: ch)]
        let cells = rects.compactMap { sheet.cropping(to: $0) }
        guard cells.count == 4 else { throw SpriteGenError.decode }

        let registered = register(cells.map { removeWhite($0) ?? $0 })

        let d = dir(character: character, action: action)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        for i in 0..<8 { try? FileManager.default.removeItem(at: d.appendingPathComponent("frame-\(i).png")) }
        var n = 0
        for (i, img) in registered.enumerated() {
            guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { continue }
            try png.write(to: d.appendingPathComponent("frame-\(i).png")); n += 1
        }
        guard n == 4 else { throw SpriteGenError.decode }
        return n
    }

    // MARK: 对齐：按角色包围盒底部居中放到统一画布 → 双脚定住、只有姿势变 → 不再跳
    private static func register(_ frames: [CGImage]) -> [CGImage] {
        let boxes = frames.map { alphaBBox($0) }
        guard boxes.allSatisfy({ $0 != nil }) else { return frames }
        let b = boxes.map { $0! }
        let maxW = b.map { $0.width }.max() ?? 0
        let maxH = b.map { $0.height }.max() ?? 0
        let cvW = Int((maxW * 1.24).rounded()), cvH = Int((maxH * 1.12).rounded())
        guard cvW > 0, cvH > 0 else { return frames }
        var out: [CGImage] = []
        for (img, box) in zip(frames, b) {
            guard let crop = img.cropping(to: box), let c = ctx(cvW, cvH) else { out.append(img); continue }
            c.clear(CGRect(x: 0, y: 0, width: cvW, height: cvH))
            let x = (CGFloat(cvW) - box.width) / 2
            // 底部居中：y=0 是画布底（CGContext 原点在左下），双脚落到底线
            c.draw(crop, in: CGRect(x: x, y: 0, width: box.width, height: box.height))
            out.append(c.makeImage() ?? img)
        }
        return out
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
        for i in 0..<8 {
            let u = dir(character: character, action: action).appendingPathComponent("frame-\(i).png")
            guard FileManager.default.fileExists(atPath: u.path), let img = NSImage(contentsOf: u) else { break }
            imgs.append(img)
        }
        return imgs
    }
}
