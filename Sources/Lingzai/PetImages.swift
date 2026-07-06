import AppKit

/// 角色图加载：从 ~/Library/Application Support/Lingzai/pets/<name>.png 读透明 PNG
enum PetImages {
    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Lingzai/pets", isDirectory: true)
    }
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if name == "cat" { return nil }                 // "cat" = 用代码画的默认猫
        if let c = cache[name] { return c }
        let url = dir.appendingPathComponent("\(name).png")
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }
    static func clearCache() { cache.removeAll() }
}
