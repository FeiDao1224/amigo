import Foundation

/// OpenAI 兼容的 /chat/completions（国内模型 + 中转站通吃）
enum LLM {
    static func chat(provider: Provider, system: String, user: String) async throws -> String {
        try await chat(provider: provider, messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ])
    }

    /// 多轮对话
    static func chat(provider: Provider, messages: [[String: Any]]) async throws -> String {
        var base = provider.baseUrl
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions") else {
            throw err("Base URL 无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 合规红线：每次请求都注入，作为最高优先级约束
        var body: [String: Any] = ["messages": Compliance.inject(into: messages)]
        if !provider.model.isEmpty { body["model"] = provider.model }   // 中转站留空则用它预设的模型
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw err("HTTP \(http.statusCode): \(txt.prefix(200))")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let msg = choices?.first?["message"] as? [String: Any]
        let content = (msg?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty { throw err("返回内容为空") }
        return content
    }

    private static func err(_ m: String) -> NSError {
        NSError(domain: "lingzai", code: 1, userInfo: [NSLocalizedDescriptionKey: m])
    }
}
