import Foundation

struct Provider: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var baseUrl: String
    var model: String
    var apiKey: String
}

struct Config: Codable {
    var providers: [Provider] = []
    var activeId: String = ""
    var eyesFollow: Bool = true
    var dockVisible: Bool = false
    var proactive: Bool = true          // 行为驱动的主动督促
    var customCard: CardData? = nil     // 问答生成的宠物性格（nil = 用默认阿豆）
    var readAloud: Bool = false         // 朗读回复（系统 TTS）
    var proactiveLLM: Bool = false      // 督促文案由 AI 生成
    var petX: Double? = nil             // 记住宠物位置
    var petY: Double? = nil
    var stealth: Bool = false           // 隐身模式：暂停观察与主动打扰
    var character: String = "cat"       // 宠物形象：cat / lazy_fish / anxious_fish / shocked_fish
    var licenseEmail: String = ""       // 激活：买家邮箱
    var licenseCode: String = ""        // 激活：离线签名激活码
    var activeAction: String = "idle"   // 当前播放的 AI 生成动作（行为驱动关闭时用）
    var behaviorDriven: Bool = true     // 行为驱动：按交互自动切动作
    var mapSlow: String = "walk"        // 慢速拖动 → 走
    var mapFast: String = "run"         // 快速拖动 → 跑
    var mapIdle: String = "idle"        // 空闲 → 待着
    var mapChat: String = "phone"       // 对话中 → 打电话
}

/// 配置持久化：~/Library/Application Support/Lingzai/config.json
enum ConfigStore {
    static var url: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Lingzai", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }
    static func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return cfg
    }
    static func save(_ cfg: Config) {
        if let data = try? JSONEncoder().encode(cfg) { try? data.write(to: url) }
    }
}

extension Provider {
    /// 从分享内容一键导入：支持 JSON，或带 query 的 URL（lingzai:// / ccswitch:// / https 等）
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

/// 预设：国内主流 + 中转站（均 OpenAI 兼容端点）
struct Preset { let key: String; let name: String; let baseUrl: String; let model: String }
let PRESETS: [Preset] = [
    .init(key: "zhipu",       name: "智谱 GLM",      baseUrl: "https://open.bigmodel.cn/api/paas/v4",              model: "glm-4-flash"),
    .init(key: "deepseek",    name: "DeepSeek",      baseUrl: "https://api.deepseek.com/v1",                       model: "deepseek-chat"),
    .init(key: "kimi",        name: "Kimi 月之暗面",  baseUrl: "https://api.moonshot.cn/v1",                        model: "moonshot-v1-8k"),
    .init(key: "qwen",        name: "通义千问",      baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus"),
    .init(key: "siliconflow", name: "硅基流动",      baseUrl: "https://api.siliconflow.cn/v1",                     model: "deepseek-ai/DeepSeek-V3"),
    .init(key: "relay",       name: "中转站",        baseUrl: "",                                                  model: ""),
]

/// 宠物性格（可由问答生成、可持久化）
struct CardData: Codable, Equatable {
    var name: String
    var species: String
    var tone: String
    var catchphrases: [String]
    var persona: String

    var systemPrompt: String {
        "你是\(name)，一只\(species)。\(tone)。口头禅：\(catchphrases.joined(separator: " / "))。\n\(persona)\n约束：你是 AI 桌宠不是真人；回复要短、口语、像随口冒个泡，控制在 30 字内。"
    }

    static let `default` = CardData(
        name: "阿豆", species: "猫", tone: "慵懒、慢半拍、嘴硬心软",
        catchphrases: ["急啥，先眯一会儿。", "……喵。", "老大，摸摸头。"],
        persona: "你是阿豆，一只住在电脑桌面上的橘猫。慵懒、爱摸鱼、嘴硬心软。你把主人叫“老大”，嘴上嫌弃、行动上关心。你绝不假装是人类、不扮演恋人或亲属，你就是一只猫。")

    /// 从大模型返回的 JSON 宽松构造
    static func fromLLM(_ d: [String: Any]) -> CardData? {
        guard let name = d["name"] as? String, let persona = d["persona"] as? String else { return nil }
        let phrases = (d["catchphrases"] as? [Any])?.compactMap { $0 as? String } ?? []
        return CardData(
            name: name,
            species: d["species"] as? String ?? "猫",
            tone: d["tone"] as? String ?? "",
            catchphrases: phrases.isEmpty ? ["……"] : phrases,
            persona: persona)
    }
}
