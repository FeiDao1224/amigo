import Foundation

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
    var activeAction: String = "idle"   // 当前播放的 AI 生成动作（行为驱动关闭时用）
    var behaviorDriven: Bool = true     // 行为驱动：按交互自动切动作
    var mapDrag: String = "walk"        // 拖动 → 播放的动作（拖越快播越快）
    var mapChat: String = "phone"       // 对话中 → 打电话
    var actionPrompts: [String: String] = [:]   // 内置动作的自定义描述覆盖（动作id → 描述）
    var customActions: [CustomAction] = []      // 用户自建动作
    var personas: [String: CardData] = [:]      // 每个形象一套性格/人设
    var clickLeft: String = "speak"             // 左键点击行为
    var clickDouble: String = "chat"            // 双击行为：默认打开对话输入框
    var clickLong: String = "chat"              // 长按行为
    var clickRight: String = "menu"             // 右键行为：固定打开右键菜单
    var rightMenuItems: [String] = ["speak", "feed", "diary", "chat", "settings", "hide", "quit"]   // 右键菜单显示哪些项（可自定义）
    var senseFrontApp: Bool = true              // 回复里带上你正在用的软件（可在交互里关）
    var autoMemory: Bool = false                // 自动从对话提取长期记忆，默认关闭
    var onboarded: Bool = false                 // 是否过了首启引导
    var seededDoubleClickChat: Bool = false     // 一次性把旧默认(双击=无)迁到"双击=对话"
    var migratedCompactPetWindow: Bool = false  // 一次性把旧宽窗(260)存的 petX 平移到窄窗(136)
    var followWindow: Bool = true               // 自动贴住你正在操作的窗口右下角
    var companionChat: Bool = true              // 偶尔按心情撒娇，不是督促干活
    var companion: CompanionSnapshot = CompanionSnapshot()
    var seededCompanionMenu: Bool = false       // 一次性把「喂食」加进右键菜单
    var seededDiaryMenu: Bool = false           // 一次性把「今天」加进右键菜单
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
        return decode(data)
    }

    /// 容错解码：严格失败时把磁盘 JSON 合并进默认配置再解，避免升级丢 Key / 形象 / 人设。
    static func decode(_ data: Data) -> Config {
        if let cfg = try? JSONDecoder().decode(Config.self, from: data) { return cfg }
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
