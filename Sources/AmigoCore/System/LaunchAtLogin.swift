import Foundation

/// 开机自启：写/删 ~/Library/LaunchAgents 里的 LaunchAgent plist
enum LaunchAtLogin {
    static let label = "com.amigo.app"
    /// 0.x 用过的旧标签，会在 ~/Library/LaunchAgents 里留下孤儿 plist，见到就清掉
    private static let legacyLabel = "com.amigo.dev"

    static var plistURL: URL { url(for: label) }
    private static func url(for label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 启动时调一次：旧标签的 plist 还在 = 用户当初开过自启，迁到新标签，别让开关无声变回关闭
    static func migrateLegacyLabel() {
        let fm = FileManager.default
        let legacy = url(for: legacyLabel)
        guard fm.fileExists(atPath: legacy.path) else { return }
        let needsNewPlist = !isEnabled   // 新标签还没写过 → 用旧标签的存在证明用户开过自启
        try? fm.removeItem(at: legacy)
        if needsNewPlist { set(true) }
    }

    static func set(_ on: Bool) {
        try? FileManager.default.removeItem(at: url(for: legacyLabel))
        if on {
            let exe = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>\(label)</string>
                <key>ProgramArguments</key>
                <array><string>\(exe)</string></array>
                <key>RunAtLoad</key><true/>
            </dict>
            </plist>
            """
            try? FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
