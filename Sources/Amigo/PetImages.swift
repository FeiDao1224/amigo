import AppKit

/// 角色图加载：从 ~/Library/Application Support/Amigo/pets/<name>.png 读透明 PNG
enum PetImages {
    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Amigo/pets", isDirectory: true)
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

    /// 打包随附的内置形象（咕咕嘎嘎=默认 + 草地牛），带动作帧
    static let builtinCharacters = ["penguin", "cow"]

    /// 首次启动：把内置形象的静态图 + 动作帧拷到本机（打包 .app 后新用户即有会动的宠物，不空白、不需模型）
    static func installDefaults() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in builtinCharacters {
            // 静态形象图
            let dst = dir.appendingPathComponent("\(name).png")
            if !fm.fileExists(atPath: dst.path),
               let src = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "pets") {
                try? fm.copyItem(at: src, to: dst)
            }
            // 动作帧 pets/generated/<name>/<action>/frame-0..3.png
            for action in ["work", "phone", "think", "idle", "run", "walk"] {
                let destDir = dir.appendingPathComponent("generated/\(name)/\(action)", isDirectory: true)
                for i in 0..<4 {
                    let fdst = destDir.appendingPathComponent("frame-\(i).png")
                    guard !fm.fileExists(atPath: fdst.path),
                          let fsrc = Bundle.main.url(forResource: "frame-\(i)", withExtension: "png",
                                                     subdirectory: "pets/generated/\(name)/\(action)") else { continue }
                    try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    try? fm.copyItem(at: fsrc, to: fdst)
                }
            }
        }
    }
}
