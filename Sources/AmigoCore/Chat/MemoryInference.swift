import Foundation

/// 从模型回复里抽出记忆条目。非法范围 / 非 JSON 一律空数组，不 trap。
enum MemoryInference {
    static func parse(_ reply: String) -> [(content: String, category: String)] {
        guard let s = reply.firstIndex(of: "["), let e = reply.lastIndex(of: "]"), s <= e,
              let data = String(reply[s...e]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let c = item["content"] as? String, !c.isEmpty else { return nil }
            return (c, (item["category"] as? String) ?? "其它")
        }
    }
}
