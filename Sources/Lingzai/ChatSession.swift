import Foundation

struct ChatMsg: Identifiable, Equatable {
    let id = UUID()
    let role: String    // user / assistant
    let content: String
}

/// 和阿豆的多轮对话 + 从对话里自动提取记忆
final class ChatSession: ObservableObject {
    @Published var messages: [ChatMsg] = []
    @Published var busy = false

    var provider: () -> Provider? = { nil }
    var systemPrompt: () -> String = { "" }                 // 人格 + 记忆
    var onReply: (String) -> Void = { _ in }                // 镜像到桌宠气泡
    var onInferred: ([(content: String, category: String)]) -> Void = { _ in }
    var isStealth: () -> Bool = { false }

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
        Task { @MainActor in
            do {
                let reply = try await LLM.chat(provider: p, messages: msgs)
                messages.append(ChatMsg(role: "assistant", content: reply))
                onReply(reply)
                if !isStealth() { extractMemory(provider: p) }
            } catch {
                let m = "（出错了：\(error.localizedDescription)）"
                messages.append(ChatMsg(role: "assistant", content: m))
                onReply(m)                   // 报错也显示到气泡
                NSLog("Lingzai chat error: \(error.localizedDescription)")
            }
            busy = false
        }
    }

    /// 后台从最近对话里抽取"关于主人"的长期事实
    private func extractMemory(provider p: Provider) {
        let convo = messages.suffix(8)
            .map { "\($0.role == "user" ? "主人" : "阿豆")：\($0.content)" }
            .joined(separator: "\n")
        let sys = """
        你从对话里抽取值得【长期记住的关于主人】的事实（偏好 / 目标 / 正在做的项目 / 常提到的人 / 情绪触发点 / 习惯）。
        只输出 JSON 数组，例：[{"content":"在做灵崽这个项目","category":"项目"}]，category 取 偏好/目标/项目/关系/情绪/任务/其它。
        没有值得记的就输出 []。绝不编造、不要记一次性的闲聊。
        """
        Task {
            guard let reply = try? await LLM.chat(provider: p, system: sys, user: convo),
                  let s = reply.firstIndex(of: "["), let e = reply.lastIndex(of: "]"),
                  let data = String(reply[s...e]).data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let items: [(content: String, category: String)] = arr.compactMap {
                guard let c = $0["content"] as? String, !c.isEmpty else { return nil }
                return (c, ($0["category"] as? String) ?? "其它")
            }
            if !items.isEmpty { await MainActor.run { self.onInferred(items) } }
        }
    }
}
