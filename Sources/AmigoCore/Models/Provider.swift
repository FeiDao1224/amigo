import Foundation
import Security

struct Provider: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var baseUrl: String
    var model: String
    var apiKey: String

    init(id: String = UUID().uuidString, name: String, baseUrl: String, model: String, apiKey: String) {
        self.id = id
        self.name = name
        self.baseUrl = baseUrl
        self.model = model
        self.apiKey = apiKey
    }

    private enum CodingKeys: String, CodingKey { case id, name, baseUrl, model, apiKey }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try values.decode(String.self, forKey: .name)
        baseUrl = try values.decode(String.self, forKey: .baseUrl)
        model = try values.decode(String.self, forKey: .model)
        // Backward compatibility: older config files may still contain a plaintext key.
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(baseUrl, forKey: .baseUrl)
        try values.encode(model, forKey: .model)
        // Keep a legacy key only when Keychain migration failed, so a failed migration never loses access.
        if !apiKey.isEmpty { try values.encode(apiKey, forKey: .apiKey) }
    }
}

enum KeychainStore {
    private static let service = "com.amigo.app.provider-key"

    static func read(_ account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
    }
}

extension Provider {
    /// 从分享内容一键导入：支持 JSON，或带 query 的 URL（amigo:// / ccswitch:// / https 等）
    static func fromImport(_ raw: String) -> Provider? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return build(obj)
        }
        if let comps = URLComponents(string: s), let items = comps.queryItems {
            var d: [String: Any] = [:]
            for it in items { d[it.name] = it.value }
            return build(d)
        }
        // Codex config.toml + auth.json / 混合文本兜底
        func rx(_ p: String) -> String? {
            guard let r = try? NSRegularExpression(pattern: p, options: [.anchorsMatchLines]) else { return nil }
            let range = NSRange(s.startIndex..., in: s)
            guard let m = r.firstMatch(in: s, range: range), m.numberOfRanges > 1,
                  let rg = Range(m.range(at: 1), in: s) else { return nil }
            return String(s[rg])
        }
        if let base = rx("base_url\\s*[=:]\\s*\"([^\"]+)\"") {
            let model = rx("^\\s*model\\s*=\\s*\"([^\"]+)\"") ?? ""
            let key = rx("(sk-[A-Za-z0-9_\\-]{16,})")
                ?? rx("OPENAI_API_KEY\"?\\s*[:=]\\s*\"([^\"]+)\"") ?? ""
            let name = URLComponents(string: base)?.host ?? "中转站"
            return Provider(name: name, baseUrl: base, model: model, apiKey: key)
        }
        return nil
    }
    private static func build(_ d: [String: Any]) -> Provider? {
        func pick(_ keys: [String]) -> String? {
            for k in keys { if let v = d[k] as? String, !v.isEmpty { return v } }
            return nil
        }
        guard let base = pick(["baseUrl", "base_url", "baseURL", "url", "endpoint", "host"]) else { return nil }
        let model = pick(["model", "models"]) ?? ""
        let key = pick(["apiKey", "api_key", "key", "token"]) ?? ""
        let name = pick(["name", "title", "provider"]) ?? (URLComponents(string: base)?.host ?? "导入的中转站")
        return Provider(name: name, baseUrl: base, model: model, apiKey: key)
    }
}
