import Foundation

/// OpenAI 兼容图像编辑（gpt-image-2）：直连用户已配置的中转站端点，无需本地 Node 服务。
/// 复用聊天 provider 的 baseUrl + apiKey；模型固定 gpt-image-2。key 只在内存/本机配置，绝不打印。
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
    /// 用 reference 图 + prompt 做 image edit，返回 PNG 字节。
    static func edit(baseUrl: String, apiKey: String, prompt: String,
                     referencePNG: Data, size: String = "1024x1024", quality: String = "medium") async throws -> Data {
        guard !baseUrl.isEmpty, !apiKey.isEmpty else { throw ImageGenError.noProvider }
        let base = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        guard let url = URL(string: base + "/images/edits") else { throw ImageGenError.decode }
        let dataURL = "data:image/png;base64," + referencePNG.base64EncodedString()

        // multipart 优先（标准 OpenAI images/edits 格式，chiyicn 已验证可用）；不认再退回 JSON image_urls。
        do {
            return try await send(multipartRequest(url: url, apiKey: apiKey, prompt: prompt,
                                                   referencePNG: referencePNG, size: size, quality: quality))
        } catch let ImageGenError.http(code, msg) {
            let m = msg.lowercased()
            let retry = [400, 404, 415, 422].contains(code)
                || m.contains("multipart") || m.contains("image_url") || m.contains("json") || m.contains("unsupported")
            guard retry else { throw ImageGenError.http(code, msg) }
            return try await send(jsonRequest(url: url, apiKey: apiKey, body: [
                "model": "gpt-image-2", "prompt": prompt, "image_urls": [dataURL],
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
                                         referencePNG: Data, size: String, quality: String) -> URLRequest {
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
        b.append("--\(boundary)\r\n".data(using: .utf8)!)
        b.append("Content-Disposition: form-data; name=\"image\"; filename=\"reference.png\"\r\n".data(using: .utf8)!)
        b.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        b.append(referencePNG); b.append("\r\n".data(using: .utf8)!)
        b.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = b
        return req
    }

    private static func send(_ req: URLRequest) async throws -> Data {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw ImageGenError.network(error.localizedDescription) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? (json?["error"] as? String)
                ?? (String(data: data, encoding: .utf8)?.prefix(300)).map(String.init) ?? "未知错误"
            throw ImageGenError.http(code, msg)
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
