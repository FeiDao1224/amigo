import Foundation

/// 一条任务（命名避开 Swift 并发的 Task）
struct TodoItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var steps: [String] = []      // 自动拆解的小步骤
    var next: String = ""         // 现在就能做的最小下一步
    var done: Bool = false
    var createdAt: Date = Date()
}

enum TodoStore {
    static var url: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Amigo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("todos.json")
    }
    static func load() -> [TodoItem] {
        guard let d = try? Data(contentsOf: url),
              let t = try? JSONDecoder().decode([TodoItem].self, from: d) else { return [] }
        return t
    }
    static func save(_ t: [TodoItem]) {
        if let d = try? JSONEncoder().encode(t) { try? d.write(to: url) }
    }
}
