import AppKit

/// 进程入口：可执行 target 只转发到这里，好让测试依赖 `AmigoCore` 而不是可执行文件。
public enum AmigoApp {
    public static func start() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        MainActor.assumeIsolated { app.delegate = delegate }
        app.run()
    }
}
