import SwiftUI
import AppKit

/// 配置状态：被设置窗观察。config 变动不频繁，不会拖慢 UI。
final class AppState: ObservableObject {
    @Published var config: Config
    @Published var memories: [Memory] = []
    @Published var tasks: [TodoItem] = []
    @Published var focusing = false               // 陪做模式中
    @Published var licensed = false               // 已激活 Pro
    var onStartFocus: ((String) -> Void)?
    var onTaskDone: ((String) -> Void)?

    init() {
        config = ConfigStore.load(); memories = MemoryStore.load(); tasks = TodoStore.load()
        licensed = License.verify(email: config.licenseEmail, code: config.licenseCode)
    }

    // MARK: 激活 / Pro
    /// 校验邮箱+激活码，通过则记住并解锁
    @discardableResult
    func activate(email: String, code: String) -> Bool {
        guard License.verify(email: email, code: code) else { return false }
        config.licenseEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        config.licenseCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        persist(); licensed = true
        return true
    }
    func deactivate() { config.licenseEmail = ""; config.licenseCode = ""; persist(); licensed = false }

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

    func setEyesFollow(_ v: Bool) { config.eyesFollow = v; persist() }
    func setProactive(_ v: Bool) { config.proactive = v; persist() }
    func setReadAloud(_ v: Bool) { config.readAloud = v; persist() }
    func setProactiveLLM(_ v: Bool) { config.proactiveLLM = v; persist() }
    func setStealth(_ v: Bool) { config.stealth = v; persist() }
    var onCharacterChanged: ((String) -> Void)?
    func setCharacter(_ id: String) { config.character = id; persist(); onCharacterChanged?(id) }

    /// 自定义形象：把用户选的图像素化，存成 custom.png 并设为当前桌宠
    @discardableResult
    func setCustomPet(from image: NSImage, rows: Int, levels: Int, flood: Bool) -> Bool {
        let url = PetImages.dir.appendingPathComponent("custom.png")
        guard Pixelizer.writePNG(image, to: url, rows: rows, levels: levels, scale: 3, flood: flood) else { return false }
        PetImages.clearCache()
        setCharacter("custom")
        return true
    }

    // MARK: 隐私 / 数据主权（它懂你，但不偷看你）
    var dataDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Lingzai", isDirectory: true)
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
        let out = dest.appendingPathComponent("灵崽数据备份", isDirectory: true)
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
        config.customCard = nil; config.character = "cat"; persist()
        PetImages.clearCache(); onCharacterChanged?("cat")
    }

    // MARK: AI 动作动画（直连你配置的模型端点，无需本地服务）
    @Published var actionStatus: [String: String] = [:]   // action → "generating"/"success"/"failed:<msg>"
    var onGeneratedFramesChanged: (() -> Void)?

    @MainActor
    func generateAction(_ action: PetAnimAction) async {
        guard let p = activeProvider(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else {
            actionStatus[action.rawValue] = "failed:先在「模型」页配置并启用一个模型"; return
        }
        let refURL = PetImages.dir.appendingPathComponent("\(config.character).png")
        guard let ref = try? Data(contentsOf: refURL), NSImage(data: ref) != nil else {
            actionStatus[action.rawValue] = "failed:当前形象没有图片可作参考（先选一个鱼 / 做个自定义形象）"; return
        }
        actionStatus[action.rawValue] = "generating"
        do {
            _ = try await SpriteGen.generate(action: action, character: config.character, referencePNG: ref, baseUrl: p.baseUrl, apiKey: p.apiKey)
            actionStatus[action.rawValue] = "success"
            onGeneratedFramesChanged?()
        } catch {
            actionStatus[action.rawValue] = "failed:\(error.localizedDescription)"
        }
    }

    func setActiveAction(_ a: String) { config.activeAction = a; persist(); onGeneratedFramesChanged?() }

    @Published var batchGenerating = false
    @Published var batchProgress = ""
    /// 一键生成全部动作（逐个，串行）
    @MainActor
    func generateAllActions() async {
        guard !batchGenerating else { return }
        batchGenerating = true
        let all = PetAnimAction.allCases
        for (i, a) in all.enumerated() {
            batchProgress = "\(i + 1)/\(all.count) \(a.title)"
            await generateAction(a)
        }
        batchGenerating = false; batchProgress = ""
    }
    func setBehaviorDriven(_ v: Bool) { config.behaviorDriven = v; persist(); onGeneratedFramesChanged?() }
    func setMap(_ trigger: String, _ action: String) {
        switch trigger {
        case "slow": config.mapSlow = action; case "fast": config.mapFast = action
        case "idle": config.mapIdle = action; case "chat": config.mapChat = action; default: break
        }
        persist(); onGeneratedFramesChanged?()
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

    // MARK: 性格
    func currentCard() -> CardData { config.customCard ?? .default }
    func setCard(_ c: CardData) { config.customCard = c; persist() }
    func resetCard() { config.customCard = nil; persist() }

    /// 问答 → 大模型生成性格
    func generatePersonality(answers: String) async -> Result<CardData, Error> {
        guard let p = activeProvider(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else {
            return .failure(NSError(domain: "lingzai", code: 0,
                                    userInfo: [NSLocalizedDescriptionKey: "先在「模型」页配置并启用一个模型"]))
        }
        do { return .success(try await PersonaDesigner.design(provider: p, answers: answers)) }
        catch { return .failure(error) }
    }
    func setDockVisible(_ v: Bool) {
        config.dockVisible = v; persist()
        NSApp.setActivationPolicy(v ? .regular : .accessory)
    }
}
