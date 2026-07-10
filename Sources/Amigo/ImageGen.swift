import Foundation

/// OpenAI 兼容图像编辑（gpt-image-2）：直连用户已配置的中转站端点，无需本地 Node 服务。
/// 复用聊天 provider 的 baseUrl + apiKey；模型固定 gpt-image-2。Key 从 macOS Keychain 取到内存后使用，绝不打印。
enum ImageGenError: LocalizedError {
    case noProvider, network(String), http(Int, String), decode
    var errorDescription: String? {
        switch self {
        case .noProvider: return "还没配置模型服务（去「模型」页配一个中转站 / OpenAI 兼容端点）"
        case .network(let s): return "网络错误：\(s)"
        case .http(let c, let m): return "生图接口返回 \(c)：\(m)"
        case .decode: return "无法解析生图返回"
        }
    }
}

enum ImageGen {
    /// 用 1~多张 reference 图 + prompt 做 image edit，返回 PNG 字节。
    static func edit(baseUrl: String, apiKey: String, prompt rawPrompt: String,
                     references: [Data], size: String = "1024x1024", quality: String = "medium") async throws -> Data {
        guard !baseUrl.isEmpty, !apiKey.isEmpty else { throw ImageGenError.noProvider }
        guard !references.isEmpty else { throw ImageGenError.decode }
        let prompt = rawPrompt + "\n" + Compliance.imageClause   // 版权/法律红线：拼进每次生图
        let base = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        guard let url = URL(string: base + "/images/edits") else { throw ImageGenError.decode }
        let dataURLs = references.map { "data:image/png;base64," + $0.base64EncodedString() }

        // multipart 优先（标准 OpenAI images/edits 格式，chiyicn 已验证可用）；不认再退回 JSON image_urls。
        do {
            return try await send(multipartRequest(url: url, apiKey: apiKey, prompt: prompt,
                                                   references: references, size: size, quality: quality))
        } catch let ImageGenError.http(code, msg) {
            let m = msg.lowercased()
            let retry = [400, 404, 415, 422].contains(code)
                || m.contains("multipart") || m.contains("image_url") || m.contains("json") || m.contains("unsupported")
            guard retry else { throw ImageGenError.http(code, msg) }
            return try await send(jsonRequest(url: url, apiKey: apiKey, body: [
                "model": "gpt-image-2", "prompt": prompt, "image_urls": dataURLs,
                "size": size, "quality": quality, "n": 1, "output_format": "png",
            ]))
        }
    }

    private static func jsonRequest(url: URL, apiKey: String, body: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 240
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func multipartRequest(url: URL, apiKey: String, prompt: String,
                                         references: [Data], size: String, quality: String) -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 240
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var b = Data()
        func field(_ name: String, _ value: String) {
            b.append("--\(boundary)\r\n".data(using: .utf8)!)
            b.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            b.append("\(value)\r\n".data(using: .utf8)!)
        }
        for (k, v) in [("model", "gpt-image-2"), ("prompt", prompt), ("size", size),
                       ("quality", quality), ("n", "1"), ("output_format", "png")] { field(k, v) }
        for (i, ref) in references.enumerated() {
            b.append("--\(boundary)\r\n".data(using: .utf8)!)
            b.append("Content-Disposition: form-data; name=\"image\"; filename=\"reference-\(i).png\"\r\n".data(using: .utf8)!)
            b.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
            b.append(ref); b.append("\r\n".data(using: .utf8)!)
        }
        b.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = b
        return req
    }

    /// 把原始错误压成一句短话：HTML/超长直接概括
    private static func sanitize(_ s: String) -> String {
        let low = s.lowercased()
        if low.contains("<!doctype") || low.contains("<html") { return "服务器返回网页错误（端点/网关/额度问题）" }
        var t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if t.count > 80 { t = String(t.prefix(80)) + "…" }
        return t
    }

    private static func send(_ req: URLRequest) async throws -> Data {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw ImageGenError.network(error.localizedDescription) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let raw = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? (json?["error"] as? String)
                ?? (String(data: data, encoding: .utf8)?.prefix(400)).map(String.init) ?? "未知错误"
            throw ImageGenError.http(code, sanitize(raw))
        }
        return try await extractImage(json)
    }

    /// 解析多种返回形状：data[0].b64_json/url、images[0]…；b64 直接解，url 则下载。
    private static func extractImage(_ json: [String: Any]?) async throws -> Data {
        func b64ToData(_ s: String) -> Data? {
            let payload = s.hasPrefix("data:")
                ? (s.firstIndex(of: ",").map { String(s[s.index(after: $0)...]) } ?? s)
                : s
            return Data(base64Encoded: payload)
        }
        let first = (json?["data"] as? [[String: Any]])?.first
            ?? (json?["images"] as? [[String: Any]])?.first
            ?? (json?["image"] as? [String: Any])
        if let b = first?["b64_json"] as? String, let d = b64ToData(b) { return d }
        if let u = first?["url"] as? String, let url = URL(string: u) {
            do { return try await URLSession.shared.data(from: url).0 }
            catch { throw ImageGenError.network(error.localizedDescription) }
        }
        throw ImageGenError.decode
    }
}
