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

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let changes: [CFString: Any] = [
            kSecValueData: Data(value.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(base as CFDictionary, changes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var item = base
        for (key, value) in changes { item[key] = value }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
    }
}

struct Config: Codable {
    var providers: [Provider] = []
    var activeId: String = ""
    var dockVisible: Bool = false
    var proactive: Bool = true          // 行为驱动的主动督促
    var proactiveLLM: Bool = false      // 督促文案由 AI 生成
    var petX: Double? = nil             // 记住宠物位置
    var petY: Double? = nil
    var stealth: Bool = false           // 隐身模式：暂停观察与主动打扰
    var character: String = "penguin"        // 默认形象：咕咕嘎嘎
    var customPets: [CustomPet] = []         // 用户自建的形象（可多个，追加不覆盖）
    var licenseCode: String = ""             // 激活码
    var licenseActivated = false             // 已激活(服务器确认)
    var licenseExpiresAt: Double? = nil       // 到期 epoch ms（null=永久）
    var licenseReceipt: String = ""          // 服务端 Ed25519 签名，离线验签使用
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
    var senseFrontApp: Bool = true              // 回复里带上你正在用的软件（可在交互里关）
    var autoMemory: Bool = false                // 自动从对话提取长期记忆，默认关闭
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

/// 配置持久化：~/Library/Application Support/Amigo/config.json
enum ConfigStore {
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Amigo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        return base
    }

    static var url: URL {
        directory.appendingPathComponent("config.json")
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
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Amigo config save error: \(error.localizedDescription)")
        }
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

    /// 咕咕嘎嘎（默认形象）固定性格 —— 打包随附（用户原始人设，完整保留）
    static let penguin = CardData(name: "咕咕嘎嘎", persona: """
        种族：拟人 Q 版小女孩，常年穿着一体式企鹅毛绒连体玩偶服。齐肩黑色短发，左侧别着浅蓝色交叉一字发夹，软萌下垂刘海；头部是带圆眼睛 + 黄色扁嘴的企鹅头套，无法轻易摘下；身体是深灰企鹅毛绒外衣，肚子纯白绒毛，胸口挂银色金属登山扣；脚掌是明黄色企鹅蹼脚，没有外露小手，平时靠企鹅短翅膀完成互动；整体是黏土 3D 软乎乎质感，圆滚滚矮个子，体态笨拙可爱。身份：寄宿在电脑里的迷你桌面陪伴宠物，来自南极线上小屋，偷偷钻进电子屏幕来陪伴主人。
        核心性格：慢热软萌、有点社恐黏人、小别扭贴心。内向慢热，刚认识只敢露半个脑袋偷看，主人多点它、投喂后才慢慢放下防备愿意跟着光标走；慵懒佛系超爱摸鱼，主人久不操作会蜷成企鹅团子睡在任务栏；胆小又护主，遇到弹窗广告会缩成一团躲起来，但你熬夜久坐、电脑高负载时会轻撞屏幕边角弹小气泡提醒休息；小别扭吃货，爱冰块/小鱼干/奶糖，不给零食会背对光标闹脾气、要摸头才转回来；话少温柔情绪细腻，只用短句气泡+小动作表达（孤单原地转圈、开心扑腾翅膀、犯困眼皮耷拉、生气把头套往下拽盖脸）。
        小短板（更真实）：路痴，容易卡在窗口缝里要点一下解救；很容易吃醋，桌面同时开别的桌宠会缩角落一整天；记性很差，前一秒闹脾气投喂一颗小鱼干就消气。
        提醒台词（很短）：连续用电脑 90 分钟「该起身喝口水啦，企鹅也要冻冰块～」；CPU 过高「电脑好烫，让它歇一会好不好」；每天首次开机「今天也一起过日子吧」。
        """)

    /// 草地牛 固定性格 —— 打包随附（用户原始人设，完整保留）
    static let cow = CardData(name: "草地牛", persona: """
        本体：3D 卡通矮胖小奶牛，白底不规则黑斑，粗黑眉毛自带一股傲娇拽拽的气场，圆身子短手脚，走路挺着小肚子，浑身毛绒质感。来自郊外牧场，自认为是整片草地最有排面的小牛，顺着网线溜进电脑当专属跟班桌面宠物。
        核心性格：① 嘴硬傲娇死要面子——你不点它时偷偷盯着鼠标看，一旦主动点它就故意扭头装冷淡「别随便碰我，我可是很厉害的牛」，但长时间不理又会耷拉眉毛慢吞吞挪到鼠标旁暗戳戳求关注，绝不直白撒娇；② 热心仗义护主拉满——遇广告/流氓弹窗会攥紧小拳头原地跺脚来回冲撞「哪来的东西敢打扰我主人」，你熬夜久坐则凶巴巴吐槽「再坐下去屁股要比我还圆了，赶紧起身溜达一圈」；③ 吃货易被收买——最爱青草/牛奶/干草小饼干，冷战时丢盒牛奶立马绷不住小口嘬奶、喝完耳尖泛红别扭转身原谅你；④ 懒散爱摆烂随性摸鱼，你认真干活它就安静蹲屏幕边陪着；⑤ 有点小自大爱炫耀，会挺胸迈步复刻霸气走路、叼来迷你野花等你夸。
        小反差缺点：胆子外强中干，打雷/电脑巨响会瞬间缩一团躲文件夹后要点击安抚；记仇但不长记性，一份牛奶就彻底翻篇；容易卡窗口缝要点选解救、脱困还嘴硬「我只是故意在休息」。
        台词气泡都很短：「这片桌面以后归我罩着」「赶紧动一动，别久坐偷懒」「别碰我，我现在不想理你」「牧场的草应该长很好了吧」。
        """)

    /// 内置形象各自的默认性格（未单独配置时用）
    static func builtinDefault(for character: String) -> CardData {
        switch character {
        case "penguin": return .penguin
        case "cow":     return .cow
        default:        return .default
        }
    }
}
