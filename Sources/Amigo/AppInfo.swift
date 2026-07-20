import Foundation

/// 版本号与仓库地址的唯一来源。
/// `tools/package-app.sh` 会从本文件读取 `version` 写进 Info.plist，改这里就够了。
enum AppInfo {
    static let version = "1.0.0"
    static let repository = "https://github.com/FeiDao1224/amigo"
    static let bundleIdentifier = "com.amigo.app"
}
