import SwiftUI
import AppKit

/// 配置状态：被设置窗观察。config 变动不频繁，不会拖慢 UI。
final class AppState: ObservableObject {
    @Published var config: Config
    @Published var memories: [Memory] = []
    @Published var tasks: [TodoItem] = []
    @Published var focusing = false               // 陪做模式中
    var onStartFocus: ((String) -> Void)?
    var onTaskDone: ((String) -> Void)?

    init() { config = ConfigStore.load(); memories = MemoryStore.load(); tasks = TodoStore.load() }

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
