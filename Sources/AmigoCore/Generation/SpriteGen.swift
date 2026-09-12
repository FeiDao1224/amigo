import AppKit
import ImageIO

/// 6 个内置动作。prompt 强调「同尺寸 / 居中 / 双脚同一基线」，配合帧对齐消除播放时的跳动。
enum PetAnimAction: String, CaseIterable, Identifiable {
    case work, phone, think, idle, walk, sleep
    var id: String { rawValue }
    var title: String {
        switch self { case .work: "工作"; case .phone: "打电话"; case .think: "思考"; case .idle: "待着"; case .walk: "走路"; case .sleep: "睡觉" }
    }
    var emoji: String {
        switch self { case .work: "💻"; case .phone: "📞"; case .think: "🤔"; case .idle: "🧍"; case .walk: "🚶"; case .sleep: "😴" }
    }
    var loopSeconds: Double {   // 一个循环的目标时长；实际帧率=帧数/时长（拖动时再乘播放倍速）
        switch self { case .work: 1.4; case .phone: 1.4; case .think: 1.8; case .idle: 2.2; case .walk: 1.1; case .sleep: 3.2 }
    }
    /// 默认动作描述（可被用户在设置里覆盖）
    var defaultDescription: String {
        switch self {
        case .work:
            return "The character is sitting at a small computer desk seen from the front, typing on a laptop. Frame1: hands resting on keyboard, neutral. Frame2: fingers pressing keys, tiny head tilt. Frame3: typing, small shoulder rise (a breath). Frame4: back to neutral. A subtle looping typing motion."
        case .phone:
            return "The character is holding a phone to their ear with one hand, talking, seen from the front. Frame1: phone at ear, mouth slightly open. Frame2: free hand makes a small gesture. Frame3: a slight nod. Frame4: neutral. A subtle looping talking motion."
        case .think:
            return "The character is in a thinking pose seen from the front, one hand near the chin, eyes looking up thoughtfully. Frame1: hand at chin. Frame2: slight head tilt. Frame3: eyes glance further up. Frame4: neutral. A subtle looping thinking motion."
        case .idle:
            return "The character stands still and relaxed, front view — a VERY SUBTLE idle loop. Frame1: neutral. Frame2: eyes blink (closed) with a tiny arm sway. Frame3: gentle breath, slight weight shift onto one foot, the other foot scuffs a little. Frame4: settle back to neutral. Keep the motion calm and minimal."
        case .walk:
            return "The character is walking to the right in side profile — an even, unhurried walk cycle. Frame1: right leg forward, left leg back, arms gently swinging. Frame2: legs passing under the body. Frame3: left leg forward, right leg back. Frame4: legs passing again. All frames show the SAME right-facing side profile with a steady stride, body upright."
        case .sleep:
            return "The character is dozing off / napping while SITTING or STANDING IN PLACE, front view, ALONE on a plain empty background. STRICT: absolutely NO bed, NO blanket, NO quilt, NO pillow, NO mattress, NO furniture and NO props of any kind — draw ONLY the character itself, the exact same body, colors and silhouette as when it is standing, just sleepy. Eyes stay CLOSED the whole time; the head slowly nods down then gently bobs back up; slow calm breathing; a tiny sleepy feeling. Very minimal, peaceful motion; the character keeps its normal upright standing pose the whole loop."
        }
    }
    var prompt: String { PetAnimAction.fullPrompt(defaultDescription) }

    /// 把动作描述拼上统一的网格 / 朝向 / 解剖约束，得到最终生图提示词
    static func fullPrompt(_ description: String) -> String {
        description + "\n\nRender this as a SMOOTH 9-frame animation loop arranged in a 3x3 grid (read left-to-right, top-to-bottom) on a SOLID FLAT MAGENTA background (pure #FF00FF bright pink-purple, a chroma-key color that will be removed later). Do NOT use this magenta color anywhere on the character itself. "
        + "The key poses described above are the main beats — interpolate gentle in-between frames so the 9 frames play back as one fluid, seamless loop (frame 9 flows naturally back into frame 1). "
        + "Detailed 32-bit pixel art, the EXACT same character design, colors and size in every one of the 9 cells. "
        + "ORIENTATION (must obey): in EVERY cell the character stands UPRIGHT and right-side-up — head near the TOP of the cell, feet at the BOTTOM; never rotated, tilted, upside-down, or mirrored; keep the exact same upright orientation and scale in all 9 cells. "
        + "ANATOMY (must obey): the character's feet / paws / hooves stay planted at the very BOTTOM of every cell; NEVER draw a foot, paw, hoof or leg near, on top of, or above the head; keep every limb naturally attached to the body, no floating, detached, or clipping-through limbs. "
        + "CRITICAL FOR ANIMATION: horizontally centered with feet resting on the SAME horizontal ground line in every cell, so all 9 frames line up perfectly when looped. "
        + "Do NOT draw any text, letters, numbers, labels, watermarks, grid lines, borders or frame dividers."
    }
}

enum SpriteGenError: LocalizedError {
    case decode
    var errorDescription: String? {
        switch self {
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

    /// 生成某动作（绑定到当前形象）：直连生图 → 3×3 切 9 帧 → 色键抠底 → 重心 + 底部对齐
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

    static let gridCols = 3, gridRows = 3, frameCount = 9    // 3×3 = 9 帧（格子更大、更稳，不易抽动）

    private static func sliceRegisterSave(_ sheet: CGImage, character: String, action: String) throws -> Int {
        let cw = sheet.width / gridCols, ch = sheet.height / gridRows
        var rects: [CGRect] = []
        for r in 0..<gridRows { for c in 0..<gridCols {   // 从左到右、从上到下读
            rects.append(CGRect(x: c * cw, y: r * ch, width: cw, height: ch))
        } }
        let cells = rects.compactMap { sheet.cropping(to: $0) }
        guard cells.count == frameCount else { throw SpriteGenError.decode }

        let clean = dropOutlierFrames(cells.map { removeChroma($0) ?? $0 })   // 去背景 + 剔除穿模/画崩的离群帧
        let registered = register(clean)

        let d = dir(character: character, action: action)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        for i in 0..<64 { try? FileManager.default.removeItem(at: d.appendingPathComponent("frame-\(i).png")) }
        var n = 0
        for (i, img) in registered.enumerated() {
            guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { continue }
            try png.write(to: d.appendingPathComponent("frame-\(i).png")); n += 1
        }
        guard n >= 5 else { throw SpriteGenError.decode }   // 剔除坏帧后帧数可少于 9，够 5 帧就算成功
        return n
    }

    /// 剔除明显离群的帧：脚跑头顶 / 画崩的那帧，轮廓高度通常异常偏高。保底留 5 帧，剔太多就不剔（避免误伤）。
    private static func dropOutlierFrames(_ frames: [CGImage]) -> [CGImage] {
        let boxes = frames.map { alphaBBox($0) }
        let heights = boxes.compactMap { $0?.height }
        guard heights.count == frames.count, heights.count >= 6 else { return frames }
        let median = heights.sorted()[heights.count / 2]
        guard median > 0 else { return frames }
        var kept: [CGImage] = []
        for (i, f) in frames.enumerated() {
            guard let h = boxes[i]?.height else { kept.append(f); continue }
            if h > median * 1.3 { continue }    // 太高 → 顶部多出一坨(穿模/脚上头)
            if h < median * 0.55 { continue }   // 太矮 → 主体被去白底吃掉了(发灰/无色/画崩)
            kept.append(f)
        }
        return kept.count >= 5 ? kept : frames
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

    /// 自适应去背景：以四角颜色为背景色，flood-fill 去掉与边相连、颜色接近背景的像素，再抹掉贴边残色。
    /// 用洋红等 chroma 背景时，白色角色不会被误当背景吃掉（这就是白牛/白肚企鹅抠图发白的修复）。
    private static func removeChroma(_ img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        guard let c = ctx(w, h), let buf = { () -> UnsafeMutableRawPointer? in
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return c.data
        }() else { return nil }
        let px = buf.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // 四角平均 = 背景色
        let corners = [0, w - 1, (h - 1) * w, (h - 1) * w + w - 1]
        var sr = 0, sg = 0, sb = 0
        for i in corners { let o = i * 4; sr += Int(px[o]); sg += Int(px[o+1]); sb += Int(px[o+2]) }
        let bgR = sr / 4, bgG = sg / 4, bgB = sb / 4
        func near(_ i: Int, _ tol: Int) -> Bool {
            let o = i * 4
            return px[o+3] > 0 && abs(Int(px[o]) - bgR) <= tol && abs(Int(px[o+1]) - bgG) <= tol && abs(Int(px[o+2]) - bgB) <= tol
        }
        var seen = [Bool](repeating: false, count: w * h)
        var st = [Int]()
        for x in 0..<w { st.append(x); st.append((h-1)*w + x) }
        for y in 0..<h { st.append(y*w); st.append(y*w + w-1) }
        while let i = st.popLast() {
            if seen[i] { continue }; seen[i] = true
            if !near(i, 50) { continue }
            let o = i*4; px[o]=0; px[o+1]=0; px[o+2]=0; px[o+3]=0
            let x = i % w, y = i / w
            if x+1 < w { st.append(i+1) }; if x > 0 { st.append(i-1) }
            if y+1 < h { st.append(i+w) }; if y > 0 { st.append(i-w) }
        }
        // 抹掉贴着透明、颜色仍接近背景的残边（消除运动漏色）
        for _ in 0..<2 {
            var kill = [Int]()
            for i in 0..<(w * h) where near(i, 90) {
                let x = i % w, y = i / w
                let edge = (x+1 < w && px[(i+1)*4+3] == 0) || (x > 0 && px[(i-1)*4+3] == 0)
                    || (y+1 < h && px[(i+w)*4+3] == 0) || (y > 0 && px[(i-w)*4+3] == 0)
                if edge { kill.append(i*4) }
            }
            if kill.isEmpty { break }
            for o in kill { px[o]=0; px[o+1]=0; px[o+2]=0; px[o+3]=0 }
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
        for i in 0..<64 {   // 读到缺帧为止：历史上用过 4 帧和 16 帧，混着也能播
            let u = dir(character: character, action: action).appendingPathComponent("frame-\(i).png")
            guard FileManager.default.fileExists(atPath: u.path), let img = NSImage(contentsOf: u) else { break }
            imgs.append(img)
        }
        return imgs
    }
}
