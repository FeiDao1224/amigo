import Foundation

/// 一条长期记忆：内容 + 类别 + 是否长期 + 来源 + 时间。全本地。
struct Memory: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var content: String
    var category: String            // 偏好/目标/项目/关系/任务/情绪/其它
    var longTerm: Bool = true       // false = 仅本地临时、不长期保留
    var source: String = "manual"   // manual / inferred / chat
    var createdAt: Date = Date()
}

/// 记忆持久化：~/Library/Application Support/Amigo/memories.json
enum MemoryStore {
    static var url: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Amigo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("memories.json")
    }
    static func load() -> [Memory] {
        guard let d = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode([Memory].self, from: d) else { return [] }
        return m
    }
    static func save(_ m: [Memory]) {
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: url) }
    }
}
