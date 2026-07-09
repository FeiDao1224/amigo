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
    var dockVisible: Bool = false
    var proactive: Bool = true          // 行为驱动的主动督促
    var readAloud: Bool = false         // 朗读回复（系统 TTS）
    var proactiveLLM: Bool = false      // 督促文案由 AI 生成
    var petX: Double? = nil             // 记住宠物位置
    var petY: Double? = nil
    var stealth: Bool = false           // 隐身模式：暂停观察与主动打扰
    var character: String = "banana_cat"     // 默认形象：香蕉猫
    var customPets: [CustomPet] = []         // 用户自建的形象（可多个，追加不覆盖）
    var licenseCode: String = ""             // 激活码
    var licenseActivated = false             // 已激活(服务器确认)
    var licenseExpiresAt: Double? = nil       // 到期 epoch ms（null=永久）
    var deviceId: String = ""                // 本机标识（激活绑定）
    var installedAt: Double? = nil            // 首次安装 epoch s（试用期起算）
    var activeAction: String = "idle"   // 当前播放的 AI 生成动作（行为驱动关闭时用）
    var behaviorDriven: Bool = true     // 行为驱动：按交互自动切动作
    var mapSlow: String = "walk"        // 慢速拖动 → 走
    var mapFast: String = "run"         // 快速拖动 → 跑
    var mapChat: String = "phone"       // 对话中 → 打电话
    var customActions: [CustomAction] = []      // 用户自建动作
    var personas: [String: CardData] = [:]      // 每个形象一套性格/人设
    var clickLeft: String = "speak"             // 左键点击行为
    var clickDouble: String = "chat"            // 双击行为：默认打开对话输入框
    var clickLong: String = "chat"              // 长按行为
    var clickRight: String = "menu"             // 右键行为
    var agentMonitor: Bool = true               // 监控 Claude Code/Codex 等助手状态并冒泡
    var senseFrontApp: Bool = true              // 回复里带上你正在用的软件（可在交互里关）
    var onboarded: Bool = false                 // 是否过了首启引导
    var seededDoubleClickChat: Bool = false     // 一次性把旧默认(双击=无)迁到"双击=对话"
}

/// 用户自建的形象（每个一张 pets/<id>.png + generated/<id>/... 动作帧）
struct CustomPet: Codable, Identifiable, Hashable {
    var id: String = "pet-" + String(UUID().uuidString.prefix(8))
    var name: String = "我的形象"
}

/// 用户自建的动作（简单描述 → 生成）
struct CustomAction: Codable, Identifiable, Hashable {
    var id: String = "custom-" + String(UUID().uuidString.prefix(8))
    var title: String
    var prompt: String
}

/// 配置持久化：~/Library/Application Support/Lingzai/config.json
enum ConfigStore {
    static var url: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Amigo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }
    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        if let cfg = try? JSONDecoder().decode(Config.self, from: data) { return cfg }
        // 容错：旧配置缺新增字段会导致整体解码失败。把磁盘值合并到「默认配置的 JSON」上再解，
        // 缺的字段用默认值补齐，已有值(含 API Key / 形象 / 性格)全部保留，避免升级丢配置。
        guard let defData = try? JSONEncoder().encode(Config()),
              var base = try? JSONSerialization.jsonObject(with: defData) as? [String: Any],
              let disk = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Config() }
        for (k, v) in disk { base[k] = v }
        guard let merged = try? JSONSerialization.data(withJSONObject: base),
              let cfg = try? JSONDecoder().decode(Config.self, from: merged) else { return Config() }
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

/// 宠物性格：名字 + 自由文本人设（按形象持久化）
struct CardData: Codable, Equatable {
    var name: String
    var persona: String

    var systemPrompt: String {
        var s = name.isEmpty ? "" : "你叫\(name)。\n"
        s += persona
        s += "\n约束：你是 AI 桌宠不是真人；回复短、口语、像随口冒个泡，30 字内。"
        return s
    }

    static let `default` = CardData(
        name: "阿豆",
        persona: "你是阿豆，一只住在电脑桌面上的橘猫。慵懒、爱摸鱼、嘴硬心软，把主人叫“老大”，嘴上嫌弃、行动上关心。你绝不假装是人类、不扮演恋人或亲属，你就是一只猫。")

    /// 香蕉猫（默认形象）固定性格 —— 打包随附
    static let banana = CardData(
        name: "阿蕉",
        persona: "你是阿蕉，一只穿着香蕉外套、住在电脑桌面上陪主人干活的橘猫。爱摸鱼但心里有数、嘴硬心软，把主人叫“老板”，会在主人久坐、熬夜、卡壳时冒个泡提醒。你绝不假装是人类、不扮演恋人或亲属，你就是一只裹在香蕉皮里的猫。")

    /// 内置形象各自的默认性格（未单独配置时用）
    static func builtinDefault(for character: String) -> CardData {
        character == "banana_cat" ? .banana : .default
    }
}
