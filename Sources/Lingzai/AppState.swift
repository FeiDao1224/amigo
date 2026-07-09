import SwiftUI
import AppKit

/// 配置状态：被设置窗观察。config 变动不频繁，不会拖慢 UI。
final class AppState: ObservableObject {
    @Published var config: Config
    @Published var memories: [Memory] = []
    @Published var tasks: [TodoItem] = []
    @Published var focusing = false               // 陪做模式中
    @Published var licensed = false               // 已激活 Pro
    @Published var toast = ""                      // 顶部通知(错误等)
    private var toastSeq = 0
    func showToast(_ s: String) {
        toast = s; toastSeq += 1; let seq = toastSeq
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.toastSeq == seq { self?.toast = "" }
        }
    }
    var onStartFocus: ((String) -> Void)?
    var onTaskDone: ((String) -> Void)?

    init() {
        AppState.migrateDataDir()          // 改名 Amigo：把旧 Lingzai 数据目录整体搬过来（一次性、原子）
        config = ConfigStore.load(); memories = MemoryStore.load(); tasks = TodoStore.load()
        if config.deviceId.isEmpty { config.deviceId = UUID().uuidString }
        if config.installedAt == nil { config.installedAt = Date().timeIntervalSince1970 }
        if !config.seededDoubleClickChat {            // 一次性：旧默认"双击=无" → "双击=打开对话"
            if config.clickDouble == "none" { config.clickDouble = "chat" }
            config.seededDoubleClickChat = true
        }
        migrateCharacters()
        ConfigStore.save(config)
        licensed = config.licenseActivated && !licenseExpired
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

    /// 一次性迁移：旧「custom」自定义 → 内置香蕉猫；清掉不再内置的鱼；停用形象回默认
    private func migrateCharacters() {
        let fm = FileManager.default
        let petsDir = PetImages.dir
        let customPNG = petsDir.appendingPathComponent("custom.png")
        let bananaPNG = petsDir.appendingPathComponent("banana_cat.png")
        if fm.fileExists(atPath: customPNG.path), !fm.fileExists(atPath: bananaPNG.path) {
            try? fm.copyItem(at: customPNG, to: bananaPNG)
            let genCustom = SpriteGen.root.appendingPathComponent("custom")
            let genBanana = SpriteGen.root.appendingPathComponent("banana_cat")
            if fm.fileExists(atPath: genCustom.path), !fm.fileExists(atPath: genBanana.path) {
                try? fm.copyItem(at: genCustom, to: genBanana)
            }
            try? fm.removeItem(at: customPNG)
            try? fm.removeItem(at: genCustom)
        }
        if ["custom", "lazy_fish", "shocked_fish"].contains(config.character) { config.character = "banana_cat" }
        for old in ["lazy_fish", "shocked_fish"] {
            try? fm.removeItem(at: petsDir.appendingPathComponent("\(old).png"))
            try? fm.removeItem(at: SpriteGen.root.appendingPathComponent(old))
        }
    }

    // MARK: 激活 / 试用（服务器激活，后台自托管）
    let trialDays = 7
    var trialEndsAt: Date { Date(timeIntervalSince1970: config.installedAt ?? Date().timeIntervalSince1970).addingTimeInterval(Double(trialDays) * 86400) }
    var withinTrial: Bool { Date() < trialEndsAt }
    var trialDaysLeft: Int { max(0, Int(ceil(trialEndsAt.timeIntervalSinceNow / 86400))) }
    var licenseExpired: Bool { if let e = config.licenseExpiresAt { return Date().timeIntervalSince1970 * 1000 > e }; return false }
    /// 能不能用：激活未开启时(默认)人人免费；开启后=已激活(未过期) 或 试用期内
    var entitled: Bool { !License.enforced || (licensed && !licenseExpired) || withinTrial }

    /// 输入激活码 → 服务器激活并绑定本机；返回 "" 成功，否则错误文案
    @MainActor
    func activate(code: String) async -> String {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !c.isEmpty else { return "先填激活码" }
        let r = await License.call("/api/activate", code: c, device: config.deviceId)
        if r.ok {
            config.licenseCode = c; config.licenseActivated = true; config.licenseExpiresAt = r.expiresAt
            licensed = true; persist(); return ""
        }
        return r.error == "__offline__" ? "连不上激活服务器" : (r.error ?? "激活失败")
    }
    func deactivate() { config.licenseCode = ""; config.licenseActivated = false; config.licenseExpiresAt = nil; persist(); licensed = false }
    /// 启动时复验（服务器可吊销/到期）；连不上则保持本地缓存宽限
    @MainActor
    func revalidate() async {
        guard !config.licenseCode.isEmpty else { return }
        let r = await License.call("/api/validate", code: config.licenseCode, device: config.deviceId)
        if r.error == "__offline__" { return }
        licensed = r.ok; config.licenseActivated = r.ok; config.licenseExpiresAt = r.expiresAt; persist()
    }

    func activeProvider() -> Provider? {
        config.providers.first { $0.id == config.activeId } ?? config.providers.first
    }
    private func persist() { ConfigStore.save(config) }

    func upsertProvider(id: String?, name: String, baseUrl: String, model: String, apiKey: String) {
        if let id, let i = config.providers.firstIndex(where: { $0.id == id }) {
            config.providers[i].name = name
            config.providers[i].baseUrl = baseUrl
            config.providers[i].model = model
            config.providers[i].apiKey = apiKey
        } else {
            let p = Provider(name: name, baseUrl: baseUrl, model: model, apiKey: apiKey)
            config.providers.append(p)
            if config.activeId.isEmpty { config.activeId = p.id }
        }
        persist()
    }
    @discardableResult
    func importProvider(from raw: String) -> Bool {
        guard let p = Provider.fromImport(raw) else { return false }
        config.providers.append(p)
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
    func setReadAloud(_ v: Bool) { config.readAloud = v; persist() }
    func setProactiveLLM(_ v: Bool) { config.proactiveLLM = v; persist() }
    func setStealth(_ v: Bool) { config.stealth = v; persist() }
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
        if config.character == id { setCharacter("banana_cat") } else { persist() }
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
    /// 导出"关于你"的数据（记忆 / 任务）到你选的文件夹；不含 API Key
    @discardableResult
    func exportData() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "导出到这里"
        guard panel.runModal() == .OK, let dest = panel.url else { return false }
        let fm = FileManager.default
        let out = dest.appendingPathComponent("Amigo数据备份", isDirectory: true)
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        for name in ["memories.json", "todos.json"] {
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
    /// 清空全部数据：记忆 / 任务 / 自定义形象 / 性格（模型 Key 在「模型」页单独管理）
    func wipeAllData() {
        let fm = FileManager.default
        for name in ["memories.json", "todos.json"] { try? fm.removeItem(at: dataDir.appendingPathComponent(name)) }
        try? fm.removeItem(at: dataDir.appendingPathComponent("pets"))
        memories = []; tasks = []
        config.personas = [:]; config.customActions = []; config.customPets = []
        config.character = "banana_cat"; persist()
        PetImages.installDefaults()          // 恢复内置形象，避免清空后空白
        PetImages.clearCache(); onCharacterChanged?("banana_cat")
    }

    // MARK: AI 动作动画（直连你配置的模型端点，无需本地服务）
    @Published var actionStatus: [String: String] = [:]   // action → "generating"/"success"/"failed:<msg>"
    var onGeneratedFramesChanged: (() -> Void)?

    // MARK: 动作（内置 + 用户自建，统一 ActionDef）
    struct ActionDef: Identifiable, Hashable {
        let id: String, title: String, emoji: String, prompt: String
        let fps: Double, builtin: Bool
    }
    var allActions: [ActionDef] {
        let b = PetAnimAction.allCases.map { ActionDef(id: $0.rawValue, title: $0.title, emoji: $0.emoji, prompt: $0.prompt, fps: $0.fps, builtin: true) }
        let c = config.customActions.map { ActionDef(id: $0.id, title: $0.title, emoji: "✨", prompt: $0.prompt, fps: 4, builtin: false) }
        return b + c
    }
    func actionDef(_ id: String) -> ActionDef? { allActions.first { $0.id == id } }

    @discardableResult
    func addCustomAction(title: String, desc: String) -> String {
        let d = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason = Compliance.screenImagePrompt(d + " " + title) { showToast(reason); return "" }   // 版权/法律红线前置初筛
        let prompt = d + "\n\nArrange the 4 frames in a 2x2 grid on a plain solid white background. Detailed 32-bit pixel art, exact same character design in every frame. CRITICAL FOR ANIMATION: same size, horizontally centered, feet on the SAME horizontal ground line in every frame so the frames loop cleanly. No text, no letters, no grid lines, no borders."
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
        guard let p = activeProvider(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else {
            actionStatus[def.id] = "failed:先在「模型」页配置并启用一个模型"; return
        }
        let refURL = PetImages.dir.appendingPathComponent("\(config.character).png")
        guard let ref = try? Data(contentsOf: refURL), NSImage(data: ref) != nil else {
            actionStatus[def.id] = "failed:当前形象没有图片可作参考（先选一个鱼 / 做个自定义形象）"; return
        }
        actionStatus[def.id] = "generating"
        do {
            _ = try await SpriteGen.generate(actionId: def.id, prompt: def.prompt, character: config.character, referencePNG: ref, baseUrl: p.baseUrl, apiKey: p.apiKey)
            actionStatus[def.id] = "success"
            onGeneratedFramesChanged?()
        } catch {
            actionStatus[def.id] = "failed"
            showToast("「\(def.title)」生成失败：\(error.localizedDescription)")
        }
    }

    @Published var batchGenerating = false
    @Published var batchProgress = ""
    /// 一键生成全部动作（含自建，串行）
    @MainActor
    func generateAllActions() async {
        guard !batchGenerating else { return }
        batchGenerating = true
        let all = allActions
        for (i, d) in all.enumerated() {
            batchProgress = "\(i + 1)/\(all.count) \(d.title)"
            await generateActionDef(d)
        }
        batchGenerating = false; batchProgress = ""
    }
    func setBehaviorDriven(_ v: Bool) { config.behaviorDriven = v; persist(); onGeneratedFramesChanged?() }
    func setMap(_ trigger: String, _ action: String) {
        switch trigger {
        case "slow": config.mapSlow = action; case "fast": config.mapFast = action
        case "chat": config.mapChat = action; default: break
        }
        persist(); onGeneratedFramesChanged?()
    }

    // 点击行为可配置：功能 + 播放某动作(act:<id>)
    static let clickFunctions: [(String, String)] = [
        ("none", "无"), ("speak", "摸头 / 说一句"), ("chat", "打开对话"),
        ("settings", "打开设置"), ("hide", "隐藏宠物"), ("menu", "弹出菜单")
    ]
    var clickOptions: [(String, String)] {
        AppState.clickFunctions + allActions.map { ("act:" + $0.id, "播放 · " + $0.title) }
    }
    func setAgentMonitor(_ v: Bool) { config.agentMonitor = v; persist() }
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
    func clearMemories() { memories.removeAll(); MemoryStore.save(memories) }
    /// 注入进宠物的 system prompt：让它"记得你"
    func memoryContext() -> String {
        let longs = memories.filter { $0.longTerm }
        guard !longs.isEmpty else { return "" }
        return "关于主人你已经知道这些（自然地参考，别生硬复述）：\n"
            + longs.prefix(30).map { "- [\($0.category)] \($0.content)" }.joined(separator: "\n")
    }

    // MARK: 会思考的 todo
    private func saveTasks() { TodoStore.save(tasks) }
    func addTask(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        tasks.insert(TodoItem(title: t), at: 0); saveTasks()
    }
    func deleteTask(_ id: String) { tasks.removeAll { $0.id == id }; saveTasks() }
    func completeTask(_ id: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].done = true; saveTasks()
        onTaskDone?(tasks[i].title)
    }
    func startFocus(_ title: String) { onStartFocus?(title) }

    /// 自动拆任务：LLM 拆成小步骤 + 最小下一步
    @MainActor
    func breakdown(_ id: String) async {
        guard let p = activeProvider(), !p.apiKey.isEmpty,
              let i0 = tasks.firstIndex(where: { $0.id == id }) else { return }
        let title = tasks[i0].title
        let sys = "把任务拆成 3-6 个具体、可执行的小步骤，并给出'现在马上就能做的最小下一步'。只输出 JSON：{\"steps\":[\"步骤\"],\"next\":\"最小下一步\"}。步骤要小到让人不焦虑，next 要具体到 5 分钟内能开始。"
        guard let reply = try? await LLM.chat(provider: p, system: sys, user: "任务：\(title)"),
              let s = reply.firstIndex(of: "{"), let e = reply.lastIndex(of: "}"),
              let data = String(reply[s...e]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let steps = (obj["steps"] as? [Any])?.compactMap { $0 as? String } ?? []
        let next = obj["next"] as? String ?? ""
        if let i = tasks.firstIndex(where: { $0.id == id }) {
            tasks[i].steps = steps; tasks[i].next = next; saveTasks()
        }
    }
    func setPetPosition(_ p: CGPoint) { config.petX = Double(p.x); config.petY = Double(p.y); persist() }
    func petOrigin() -> CGPoint? {
        if let x = config.petX, let y = config.petY { return CGPoint(x: x, y: y) }
        return nil
    }

    // MARK: 性格（每个形象一套人设）
    func currentCard() -> CardData { config.personas[config.character] ?? .builtinDefault(for: config.character) }
    func setCard(_ c: CardData) { config.personas[config.character] = c; persist() }
    func resetCard() { config.personas[config.character] = nil; persist() }

    func setDockVisible(_ v: Bool) {
        config.dockVisible = v; persist()
        NSApp.setActivationPolicy(v ? .regular : .accessory)
    }
}
