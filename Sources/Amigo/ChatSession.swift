import Foundation

struct ChatMsg: Identifiable, Equatable, Codable {
    var id = UUID()
    let role: String    // user / assistant
    let content: String
}

/// 聊天记录持久化：~/Library/Application Support/Amigo/chat.json（保留最近 200 条）
enum ChatStore {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Amigo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("chat.json")
    }
    static func load() -> [ChatMsg] {
        guard let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([ChatMsg].self, from: d) else { return [] }
        return m
    }
    static func save(_ m: [ChatMsg]) {
        if let d = try? JSONEncoder().encode(Array(m.suffix(200))) { try? d.write(to: url) }
    }
}

/// 和桌宠的多轮对话 + 从对话里自动提取记忆
@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ChatMsg] = [] { didSet { ChatStore.save(messages) } }
    @Published var busy = false

    init() { messages = ChatStore.load() }

    var provider: () -> Provider? = { nil }
    var systemPrompt: () -> String = { "" }                 // 人格 + 记忆
    var onReply: (String) -> Void = { _ in }                // 镜像到桌宠气泡
    var onInferred: ([(content: String, category: String)]) -> Void = { _ in }
    var isStealth: () -> Bool = { false }
    var shouldInferMemory: () -> Bool = { false }

    private var replyTask: Task<Void, Never>?
    private var memoryTask: Task<Void, Never>?
    private var replyGeneration = 0
    private var memoryGeneration = 0

    func invalidateMemoryRequests() {
        memoryGeneration += 1
        memoryTask?.cancel()
        memoryTask = nil
    }

    func clear() {
        replyGeneration += 1
        replyTask?.cancel()
        replyTask = nil
        invalidateMemoryRequests()
        busy = false
        messages = []
    }

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !busy else { return }
        messages.append(ChatMsg(role: "user", content: t))
        guard let p = provider(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else {
            let m = "（先在设置→模型里配一个模型，并点“启用”）"
            messages.append(ChatMsg(role: "assistant", content: m))
            onReply(m)                       // 失败也要显示到气泡
            return
        }
        busy = true
        var msgs: [[String: Any]] = [["role": "system", "content": systemPrompt()]]
        msgs += messages.suffix(12).map { ["role": $0.role, "content": $0.content] }
        let generation = replyGeneration
        let memoryVersion = memoryGeneration
        replyTask = Task { @MainActor in
            do {
                let reply = try await LLM.chat(provider: p, messages: msgs)
                guard !Task.isCancelled, generation == replyGeneration else { return }
                messages.append(ChatMsg(role: "assistant", content: reply))
                onReply(reply)
                if memoryVersion == memoryGeneration && shouldInferMemory() && !isStealth() { extractMemory(provider: p) }
            } catch {
                guard !Task.isCancelled, generation == replyGeneration else { return }
                let m = "（出错了：\(error.localizedDescription)）"
                messages.append(ChatMsg(role: "assistant", content: m))
                onReply(m)                   // 报错也显示到气泡
                NSLog("Amigo chat error: \(error.localizedDescription)")
            }
            busy = false
        }
    }

    /// 后台从最近对话里抽取"关于主人"的长期事实
    private func extractMemory(provider p: Provider) {
        let convo = messages.suffix(8)
            .map { "\($0.role == "user" ? "主人" : "桌宠")：\($0.content)" }
            .joined(separator: "\n")
        let sys = """
        你从对话里抽取值得【长期记住的关于主人】的事实（偏好 / 目标 / 正在做的项目 / 常提到的人 / 情绪触发点 / 习惯）。
        只输出 JSON 数组，例：[{"content":"在做Amigo这个项目","category":"项目"}]，category 取 偏好/目标/项目/关系/情绪/任务/其它。
        没有值得记的就输出 []。绝不编造、不要记一次性的闲聊。
        """
        memoryTask?.cancel()
        let generation = memoryGeneration
        memoryTask = Task { @MainActor in
            guard let reply = try? await LLM.chat(provider: p, system: sys, user: convo),
                  let s = reply.firstIndex(of: "["), let e = reply.lastIndex(of: "]"), s <= e,
                  let data = String(reply[s...e]).data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let items: [(content: String, category: String)] = arr.compactMap {
                guard let c = $0["content"] as? String, !c.isEmpty else { return nil }
                return (c, ($0["category"] as? String) ?? "其它")
            }
            guard !Task.isCancelled, generation == memoryGeneration,
                  shouldInferMemory(), !isStealth() else { return }
            if !items.isEmpty { onInferred(items) }
        }
    }
}
