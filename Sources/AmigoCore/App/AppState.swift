import SwiftUI
import AppKit

/// 配置状态：被设置窗观察。config 变动不频繁，不会拖慢 UI。
final class AppState: ObservableObject {
    @Published var config: Config
    @Published var memories: [Memory] = []
    @Published var toast = ""                      // 顶部通知(错误等)
    @Published var settingsPage = "companion"     // 设置侧栏当前页，只活在进程里
    private var toastSeq = 0
    func showToast(_ s: String) {
        toast = s; toastSeq += 1; let seq = toastSeq
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.toastSeq == seq { self?.toast = "" }
        }
    }
    init() {
        AppState.migrateDataDir()          // 改名 Amigo：把旧 Lingzai 数据目录整体搬过来（一次性、原子）
        config = ConfigStore.load(); memories = MemoryStore.load()
        if !config.seededDoubleClickChat {            // 一次性：旧默认"双击=无" → "双击=打开对话"
            if config.clickDouble == "none" { config.clickDouble = "chat" }
            config.seededDoubleClickChat = true
        }
        migrateProviderSecretsBack()
        migrateCharacters()
        migrateCompactPetWindow()
        if !config.seededCompanionMenu {
            if !config.rightMenuItems.contains("feed") {
                if let i = config.rightMenuItems.firstIndex(of: "speak") {
                    config.rightMenuItems.insert("feed", at: i + 1)
                } else {
                    config.rightMenuItems.insert("feed", at: 0)
                }
            }
            config.seededCompanionMenu = true
        }
        if !config.seededDiaryMenu {
            if !config.rightMenuItems.contains("diary") {
                if let i = config.rightMenuItems.firstIndex(of: "feed") {
                    config.rightMenuItems.insert("diary", at: i + 1)
                } else if let i = config.rightMenuItems.firstIndex(of: "speak") {
                    config.rightMenuItems.insert("diary", at: i + 1)
                } else {
                    config.rightMenuItems.insert("diary", at: 0)
                }
            }
            config.seededDiaryMenu = true
        }
        ConfigStore.save(config)
    }

    /// 一次性迁移：宠物窗从 260 宽收成 PetLayout.compact 后，旧配置存的左下角 x 会让宠物左偏。
    /// 按「保持宠物中心不动」把 petX 右移半个宽度差；y 是底边对齐的，不用动。
    private func migrateCompactPetWindow() {
        defer { config.migratedCompactPetWindow = true }
        guard !config.migratedCompactPetWindow, let x = config.petX else { return }
        let shifted = x + (260 - PetLayout.compact.width) / 2
        // 别把它挪出屏幕：夹回宠物所在屏幕的可视区
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: x, y: config.petY ?? 0)) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            config.petX = min(max(shifted, vf.minX), vf.maxX - PetLayout.compact.width)
        } else {
            config.petX = shifted
        }
    }

    /// 一次性：把旧「Lingzai」数据目录改名为「Amigo」，保住已配置的模型 Key / 形象 / 记忆
    static func migrateDataDir() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let old = base.appendingPathComponent("Lingzai"), new = base.appendingPathComponent("Amigo")
        let fm = FileManager.default
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }
    }

    /// 一次性迁移：清掉已停用的旧内置形象；当前形象无效则回默认（咕咕嘎嘎）
    private func migrateCharacters() {
        let fm = FileManager.default
        let petsDir = PetImages.dir
        // 清掉不再内置的旧形象文件
        for old in ["banana_cat", "anxious_fish", "lazy_fish", "shocked_fish", "custom"] {
            try? fm.removeItem(at: petsDir.appendingPathComponent("\(old).png"))
            try? fm.removeItem(at: SpriteGen.root.appendingPathComponent(old))
        }
        // 当前形象若指向已删除/不存在的形象 → 回默认
        let valid = PetImages.builtinCharacters + config.customPets.map { $0.id }
        if !valid.contains(config.character) { config.character = "penguin" }
    }

    func activeProvider() -> Provider? {
        config.providers.first { $0.id == config.activeId } ?? config.providers.first
    }
    private func persist() { ConfigStore.save(config) }

    /// 一次性：把曾经存进 Keychain 的 key 取回到本地 config（改回“只存本地”）。
    /// 只有成功读回才删 Keychain——读不到就保留，绝不因读取失败而销毁 key。
    private func migrateProviderSecretsBack() {
        var changed = false
        for i in config.providers.indices where config.providers[i].apiKey.isEmpty {
            let id = config.providers[i].id
            if let k = KeychainStore.read(id), !k.isEmpty {
                config.providers[i].apiKey = k
                KeychainStore.delete(id)
                changed = true
            }
        }
        if changed { ConfigStore.save(config) }
    }

    func hasCredential(for providerId: String) -> Bool {
        config.providers.first(where: { $0.id == providerId })?.apiKey.isEmpty == false
    }
    func credential(for providerId: String) -> String? {
        config.providers.first(where: { $0.id == providerId })?.apiKey
    }

    @discardableResult
    func upsertProvider(id: String?, name: String, baseUrl: String, model: String, apiKey: String?) -> Bool {
        if let id, let i = config.providers.firstIndex(where: { $0.id == id }) {
            config.providers[i].name = name
            config.providers[i].baseUrl = baseUrl
            config.providers[i].model = model
            if let apiKey, !apiKey.isEmpty { config.providers[i].apiKey = apiKey }   // 留空=不改原 key
        } else {
            guard let apiKey, !apiKey.isEmpty else { showToast("请填写 API Key"); return false }
            let p = Provider(name: name, baseUrl: baseUrl, model: model, apiKey: apiKey)
            config.providers.append(p)
            if config.activeId.isEmpty { config.activeId = p.id }
        }
        persist()
        return true
    }
    @discardableResult
    func importProvider(from raw: String) -> Bool {
        guard let p = Provider.fromImport(raw) else { return false }
        config.providers.append(p)          // key 直接存本地 config
        if config.activeId.isEmpty { config.activeId = p.id }
        persist()
        return true
    }
    func deleteProvider(_ id: String) {
        config.providers.removeAll { $0.id == id }
        if config.activeId == id { config.activeId = config.providers.first?.id ?? "" }
        persist()
    }
    func setActive(_ id: String) { config.activeId = id; persist() }

    func setProactive(_ v: Bool) { config.proactive = v; persist() }
    func setProactiveLLM(_ v: Bool) { config.proactiveLLM = v; persist() }
    func setStealth(_ v: Bool) { config.stealth = v; if v { onMemoryInvalidated?() }; persist() }
    func setAutoMemory(_ v: Bool) { config.autoMemory = v; if !v { onMemoryInvalidated?() }; persist() }
    var onCharacterChanged: ((String) -> Void)?
    func setCharacter(_ id: String) { config.character = id; persist(); onCharacterChanged?(id) }

    /// 自定义形象：把用户选的图像素化，存成新形象槽（追加，不覆盖当前形象）并设为当前桌宠
    @discardableResult
    func setCustomPet(from image: NSImage, rows: Int, levels: Int, cutout: Bool) -> Bool {
        let pet = CustomPet()
        let url = PetImages.dir.appendingPathComponent("\(pet.id).png")
        guard Pixelizer.writePNG(image, to: url, rows: rows, levels: levels, scale: 3, cutout: cutout) else { return false }
        config.customPets.append(pet)
        PetImages.clearCache()
        setCharacter(pet.id)          // 追加后切到新形象（内部会 persist）
        return true
    }

    /// 删除某个自定义形象（内置形象不可删）
    func deleteCustomPet(_ id: String) {
        guard config.customPets.contains(where: { $0.id == id }) else { return }
        config.customPets.removeAll { $0.id == id }
        config.personas[id] = nil
        try? FileManager.default.removeItem(at: PetImages.dir.appendingPathComponent("\(id).png"))
        try? FileManager.default.removeItem(at: SpriteGen.root.appendingPathComponent(id))
        PetImages.clearCache()
        if config.character == id { setCharacter("penguin") } else { persist() }
        onGeneratedFramesChanged?()
    }

    // 有模型时：用 AI 把 1~3 张参考图生成更精致的像素形象（非生物自动拟人化加四肢）
    @Published var customBusy = false
    @Published var customMsg = ""
    var hasModel: Bool { let p = activeProvider(); return (p?.apiKey.isEmpty == false) && (p?.baseUrl.isEmpty == false) }

    @MainActor
    func setCustomPetAI(images: [NSImage], anthropomorphize: Bool, pixelLevel: Double, description: String) async {
        guard let p = activeProvider(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else { customMsg = "先在「模型」页配一个模型"; return }
        if let reason = Compliance.screenImagePrompt(description) { customMsg = reason; return }   // 版权/法律红线前置初筛
        let refs = Array(images.prefix(3)).compactMap { $0.pngData() }
        guard !refs.isEmpty else { customMsg = "先加一张图"; return }
        var prompt = "Recreate the SPECIFIC character shown in the reference image(s) as one single desktop-pet mascot — a faithful, recognizable likeness of THIS exact character, NOT a generic version of its species. "
        prompt += "Preserve its identity precisely: the exact colors and the shape & placement of its markings / patches / patterns, its facial features (eye shape, eyebrows, nose, mouth, cheek blush, ears / horns), its head-to-body proportions, and above all its expression and mood — so anyone seeing the reference instantly recognizes it as the same character. "
        prompt += "Front-facing, full body, standing upright, centered. Stylize it into a cute mascot but keep the likeness: it should read as the same character — similar in spirit, not a pixel-perfect photo copy. "
        if anthropomorphize {
            prompt += " If the subject is an object / food / logo / plant / anything WITHOUT a body or limbs, ANTHROPOMORPHIZE it: give it a simple cute face, two small cartoon arms and two legs so it can stand, walk and be animated."
        } else {
            prompt += " Keep its natural form and silhouette; do NOT add limbs or a face it doesn't already have."
        }
        if pixelLevel > 0.66 {
            prompt += " Chunky low-resolution 8-bit pixel art with big blocky pixels and a very limited palette."
        } else if pixelLevel > 0.33 {
            prompt += " Clean 16-bit pixel art, bold 1px outline, limited palette."
        } else {
            prompt += " Detailed 32-bit pixel art with fine pixels and soft shading."
        }
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { prompt += " Extra request from the user: \(d)." }
        prompt += " Fully transparent background, no text, no extra objects, no background scenery."
        customBusy = true; customMsg = "AI 生成中…（约 30–90s）"
        do {
            let data = try await ImageGen.edit(baseUrl: p.baseUrl, apiKey: p.apiKey, prompt: prompt, references: refs, size: "1024x1024", quality: "medium")
            guard let img = NSImage(data: data) else { customBusy = false; customMsg = "生成结果解析失败"; return }
            let cleaned = Pixelizer.cutoutImage(img) ?? img
            let pet = CustomPet()
            let url = PetImages.dir.appendingPathComponent("\(pet.id).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let png = cleaned.pngData() { try? png.write(to: url) }
            config.customPets.append(pet)
            PetImages.clearCache(); setCharacter(pet.id)   // 追加新形象，不覆盖当前
            customBusy = false; customMsg = "已生成"
        } catch {
            customBusy = false; customMsg = ""
            showToast("形象生成失败：\(error.localizedDescription)")
        }
    }

    // MARK: 隐私 / 数据主权（它懂你，但不偷看你）
    var dataDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Amigo", isDirectory: true)
    }
    /// 在访达里定位数据文件夹（让你亲眼看见数据都在本机）
    func revealDataFolder() {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dataDir])
    }
    /// 导出"关于你"的数据（记忆 + 聊天记录）到你选的文件夹；不含 API Key
    @discardableResult
    func exportData() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "导出到这里"
        guard panel.runModal() == .OK, let dest = panel.url else { return false }
        let fm = FileManager.default
        let out = dest.appendingPathComponent("Amigo数据备份", isDirectory: true)
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        for name in ["memories.json", "chat.json"] {   // 和设置页承诺的「聊天记录 + 记忆」保持一致
            let src = dataDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = out.appendingPathComponent(name)
            try? fm.removeItem(at: dst); try? fm.copyItem(at: src, to: dst)
        }
        NSWorkspace.shared.activateFileViewerSelecting([out])
        return true
    }
    /// 忘记我：只清记忆，保留模型与性格
    func forgetMe() { clearMemories() }
    /// 清空全部数据：记忆 / 自定义形象 / 性格（模型 Key 在「模型」页单独管理）
    func wipeAllData() {
        batchTask?.cancel()
        let fm = FileManager.default
        try? fm.removeItem(at: dataDir.appendingPathComponent("memories.json"))
        try? fm.removeItem(at: dataDir.appendingPathComponent("chat.json"))
        try? fm.removeItem(at: dataDir.appendingPathComponent("pets"))
        try? fm.removeItem(at: dataDir.appendingPathComponent("agents"))
        memories = []
        config.personas = [:]; config.customActions = []; config.customPets = []
        config.character = "penguin"; config.activeAction = "idle"
        config.companion = CompanionSnapshot()
        config.petX = nil; config.petY = nil; persist()
        onCompanionChanged?(config.companion)
        PetImages.installDefaults()          // 恢复内置形象，避免清空后空白
        PetImages.clearCache(); onCharacterChanged?("penguin")
        onLocalContentWiped?()
    }

    var onMemoryInvalidated: (() -> Void)?
    var onLocalContentWiped: (() -> Void)?

    // MARK: AI 动作动画（直连你配置的模型端点，无需本地服务）
    @Published var actionStatus: [String: String] = [:]   // action → "generating"/"success"/"failed:<msg>"
    var onGeneratedFramesChanged: (() -> Void)?

    // MARK: 动作（内置 + 用户自建，统一 ActionDef）
    struct ActionDef: Identifiable, Hashable {
        let id: String, title: String, emoji: String
        let description: String   // 可编辑的动作描述
        let prompt: String        // 最终生图提示词（description + 网格约束）
        let loopSeconds: Double, builtin: Bool
    }
    var builtinActions: [ActionDef] {   // 内置 6 个（描述可被 config.actionPrompts 覆盖）
        PetAnimAction.allCases.map { a in
            let desc = config.actionPrompts[a.rawValue] ?? a.defaultDescription
            return ActionDef(id: a.rawValue, title: a.title, emoji: a.emoji,
                             description: desc, prompt: PetAnimAction.fullPrompt(desc),
                             loopSeconds: a.loopSeconds, builtin: true)
        }
    }
    var allActions: [ActionDef] {
        let c = config.customActions.map { ActionDef(id: $0.id, title: $0.title, emoji: "✨", description: $0.prompt, prompt: $0.prompt, loopSeconds: 1.6, builtin: false) }
        return builtinActions + c
    }
    /// 编辑内置动作描述：改了就存覆盖、清空恢复默认
    func setActionPrompt(_ id: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == (PetAnimAction(rawValue: id)?.defaultDescription ?? "") {
            config.actionPrompts[id] = nil
        } else {
            config.actionPrompts[id] = t
        }
        persist()
    }

    @discardableResult
    func addCustomAction(title: String, desc: String) -> String {
        let d = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        if config.customActions.count >= 10 { showToast("动作最多 16 个（内置 6 + 自建 10），先删掉一些再加"); return "" }
        if let reason = Compliance.screenImagePrompt(d + " " + title) { showToast(reason); return "" }   // 版权/法律红线前置初筛
        let prompt = d + "\n\nRender this as a smooth 9-frame animation loop in a 3x3 grid (read left-to-right, top-to-bottom) on a plain solid white background. Interpolate gentle in-between frames so the loop is fluid and seamless. In EVERY cell the character stands UPRIGHT and right-side-up — head near the top, feet at the bottom; never rotated, tilted, upside-down or mirrored. Detailed 32-bit pixel art, the EXACT same character design, colors and size in every cell; horizontally centered with feet on the SAME horizontal ground line so all 9 frames line up. No text, no letters, no grid lines, no borders."
        let a = CustomAction(title: title.trimmingCharacters(in: .whitespaces).isEmpty ? "自定义动作" : title, prompt: prompt)
        config.customActions.append(a); persist()
        return a.id
    }
    func deleteCustomAction(_ id: String) {
        config.customActions.removeAll { $0.id == id }
        if config.activeAction == id { config.activeAction = "idle" }
        persist(); onGeneratedFramesChanged?()
    }

    func setActiveAction(_ a: String) { config.activeAction = a; persist(); onGeneratedFramesChanged?() }

    @MainActor
    func generateActionDef(_ def: ActionDef) async {
        await generateActionDef(def, character: config.character)
    }

    @MainActor
    private func generateActionDef(_ def: ActionDef, character: String) async {
        guard let p = activeProvider(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else {
            actionStatus[def.id] = "failed:先在「模型」页配置并启用一个模型"; return
        }
        let refURL = PetImages.dir.appendingPathComponent("\(character).png")
        guard let ref = try? Data(contentsOf: refURL), NSImage(data: ref) != nil else {
            actionStatus[def.id] = "failed:当前形象没有可用作参考的图片，先在「形象」页换一个或新建"; return
        }
        actionStatus[def.id] = "generating"
        do {
            _ = try await SpriteGen.generate(actionId: def.id, prompt: def.prompt, character: character, referencePNG: ref, baseUrl: p.baseUrl, apiKey: p.apiKey)
            guard !Task.isCancelled else { actionStatus[def.id] = "cancelled"; return }
            actionStatus[def.id] = "success"
            onGeneratedFramesChanged?()
        } catch {
            if Task.isCancelled {
                actionStatus[def.id] = "cancelled"
                return
            }
            actionStatus[def.id] = "failed"
            showToast("「\(def.title)」生成失败：\(error.localizedDescription)")
        }
    }

    @Published var batchGenerating = false
    @Published var batchProgress = ""
    private var batchTask: Task<Void, Never>?

    @MainActor
    func startGenerateAllActions() {
        guard batchTask == nil else { return }
        batchTask = Task { [weak self] in await self?.generateAllActions() }
    }

    @MainActor
    func cancelGenerateAllActions() {
        batchTask?.cancel()
    }

    /// 一键生成：只生成内置 6 个默认动作（自建动作各自单独生成）
    @MainActor
    func generateAllActions() async {
        guard !batchGenerating else { return }
        batchGenerating = true
        defer {
            batchGenerating = false
            batchProgress = ""
            batchTask = nil
        }
        let character = config.character
        let all = builtinActions
        for (i, d) in all.enumerated() {
            guard !Task.isCancelled else { return }
            batchProgress = "\(i + 1)/\(all.count) \(d.title)"
            await generateActionDef(d, character: character)
        }
    }
    func setBehaviorDriven(_ v: Bool) { config.behaviorDriven = v; persist(); onGeneratedFramesChanged?() }
    func setMap(_ trigger: String, _ action: String) {
        switch trigger {
        case "drag": config.mapDrag = action
        case "chat": config.mapChat = action; default: break
        }
        persist(); onGeneratedFramesChanged?()
    }
    /// 右键菜单勾选：加/去某一项
    func setRightMenuItem(_ id: String, _ on: Bool) {
        if on { if !config.rightMenuItems.contains(id) { config.rightMenuItems.append(id) } }
        else { config.rightMenuItems.removeAll { $0 == id } }
        persist()
    }

    // 点击行为可配置：功能 + 播放某动作(act:<id>)
    static let clickFunctions: [(String, String)] = [
        ("none", "无"), ("speak", "摸摸 / 说一句"), ("feed", "喂一口"),
        ("diary", "今天来过没有"), ("chat", "打开对话"),
        ("settings", "打开设置"), ("hide", "隐藏宠物"), ("menu", "弹出菜单")
    ]
    func setCompanionChat(_ v: Bool) { config.companionChat = v; persist() }

    var onCompanionChanged: ((CompanionSnapshot) -> Void)?

    @discardableResult
    func noteCompanion(_ event: CompanionEvent, now: Date = Date(), idleSeconds: Double = 0) -> String? {
        let hour = Calendar.current.component(.hour, from: now)
        let (next, line) = CompanionPolicy.apply(config.companion, event: event, now: now, hour: hour, idleSeconds: idleSeconds)
        if next != config.companion {
            config.companion = next
            persist()
            onCompanionChanged?(next)
        }
        return line
    }

    func companionHello() -> String {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        _ = noteCompanion(.tick, now: now)
        return CompanionPolicy.hello(config.companion, now: now, hour: hour)
    }
    var clickOptions: [(String, String)] {
        AppState.clickFunctions + allActions.map { ("act:" + $0.id, "播放 · " + $0.title) }
    }
    func setSenseFrontApp(_ v: Bool) { config.senseFrontApp = v; persist() }
    func setFollowWindow(_ v: Bool) { config.followWindow = v; persist() }
    func markOnboarded() { config.onboarded = true; persist() }
    func setClick(_ trigger: String, _ v: String) {
        switch trigger {
        case "left": config.clickLeft = v; case "double": config.clickDouble = v
        case "long": config.clickLong = v; case "right": config.clickRight = v; default: break
        }
        persist()
    }

    // MARK: 长期记忆
    func addMemory(content: String, category: String, longTerm: Bool) {
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        memories.insert(Memory(content: c, category: category, longTerm: longTerm), at: 0)
        MemoryStore.save(memories)
    }
    /// 自动记忆：从对话提取，去重后写入
    func addInferred(_ items: [(content: String, category: String)]) {
        var changed = false
        for it in items {
            let c = it.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !c.isEmpty, !memories.contains(where: { $0.content == c }) else { continue }
            memories.insert(Memory(content: c, category: it.category, source: "inferred"), at: 0)
            changed = true
        }
        if changed { MemoryStore.save(memories) }
    }
    func deleteMemory(_ id: String) { memories.removeAll { $0.id == id }; MemoryStore.save(memories) }
    func clearMemories() { onMemoryInvalidated?(); memories.removeAll(); MemoryStore.save(memories) }
    /// 注入进宠物的 system prompt：让它"记得你"
    func memoryContext() -> String {
        let longs = memories.filter { $0.longTerm }
        var parts: [String] = []
        let c = config.companion
        parts.append("你现在心情是「\(c.mood.title)」，亲密度 \(c.affection)/100，已经陪了 \(c.daysTogether) 天。自然地带一点这种心情，别报数字。")
        parts.append(CompanionPolicy.todayCaption(c.today) + " " + CompanionPolicy.todayDetail(c.today))
        if let d = c.diary.first {
            parts.append("你最近在日记里写过：「\(d.line)」带一点这种感觉就好，别朗读日记。")
        }
        if !longs.isEmpty {
            parts.append("关于主人你已经知道这些（自然地参考，别生硬复述）：\n"
                + longs.prefix(30).map { "- [\($0.category)] \($0.content)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    func setPetPosition(_ p: CGPoint) { config.petX = Double(p.x); config.petY = Double(p.y); persist() }
    func petOrigin() -> CGPoint? {
        if let x = config.petX, let y = config.petY { return CGPoint(x: x, y: y) }
        return nil
    }

    // MARK: 性格（每个形象一套人设）
    func currentCard() -> CardData { config.personas[config.character] ?? .builtinDefault(for: config.character) }
    func setCard(_ c: CardData) { config.personas[config.character] = c; persist() }

    func setDockVisible(_ v: Bool) {
        config.dockVisible = v; persist()
        NSApp.setActivationPolicy(v ? .regular : .accessory)
    }
}
