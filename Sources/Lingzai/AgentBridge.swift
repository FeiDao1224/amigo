import Foundation

/// 助手监控（借鉴 ping-island 的 hook 桥接）：Claude Code / Codex 等的 hook 把状态写进
/// ~/Library/Application Support/Lingzai/agents/<agent>.json，桌宠盯着它 → 用冒泡告诉你。
struct AgentStatus: Codable {
    let agent: String
    let state: String          // working / attention / done / error / limit
    var detail: String?
    var cwd: String?
    let time: Double           // epoch s
}

@MainActor
final class AgentBridge {
    private let runtime: PetRuntime
    private var timer: Timer?
    private var last: [String: String] = [:]     // agent → 上次 state（去重，避免刷屏）
    private var seeded = false
    var isEnabled: () -> Bool = { true }

    init(runtime: PetRuntime) { self.runtime = runtime }

    static var dir: URL {
        PetImages.dir.deletingLastPathComponent().appendingPathComponent("agents", isDirectory: true)
    }
    static var scriptPath: URL {
        PetImages.dir.deletingLastPathComponent().appendingPathComponent("bin/agent-hook.sh")
    }

    func start() {
        installScript()
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        guard isEnabled() else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f),
                  let s = try? JSONDecoder().decode(AgentStatus.self, from: d),
                  Date().timeIntervalSince1970 - s.time < 3600 else { continue }   // 忽略 1 小时前的旧状态
            if last[s.agent] == s.state { continue }
            last[s.agent] = s.state
            if !seeded { continue }                // 启动首扫只记录、不回放旧状态
            react(s)
        }
        seeded = true
    }

    private func react(_ s: AgentStatus) {
        let who = s.agent
        let msg: String
        switch s.state {
        case "working":
            let what = (s.detail?.isEmpty == false) ? "：\(s.detail!)" : "…"
            msg = "\(who) 开工了\(what)"; runtime.oneShot("work", seconds: 3)
        case "attention": msg = "\(who) 卡住了，等你确认一下 👀"
        case "done":      msg = "\(who) 跑完啦 ✓"
        case "error":     msg = "\(who) 好像报错了…"
        case "limit":     msg = "\(who) 到额度上限了"
        default:          msg = "\(who)：\(s.state)"
        }
        runtime.showBubble(msg)
    }

    // 把桥接脚本写到本机固定路径（供各助手 hook 调用），装 app 后也稳定
    private func installScript() {
        let p = Self.scriptPath
        try? FileManager.default.createDirectory(at: p.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = #"""
        #!/bin/bash
        # 灵崽 · 助手状态桥：AI 助手的 hook 调它，把状态喂给桌宠
        STATE="${1:-working}"; AGENT="${2:-Claude Code}"
        DIR="$HOME/Library/Application Support/Lingzai/agents"; mkdir -p "$DIR"
        IN="$(cat 2>/dev/null)"
        META="$(printf '%s' "$IN" | /usr/bin/python3 -c 'import sys,json
        try:
         d=json.load(sys.stdin); print((d.get("tool_name") or d.get("message") or "")+"\t"+(d.get("cwd") or ""))
        except: print("\t")' 2>/dev/null)"
        DETAIL="${META%%$'\t'*}"; CWD="${META#*$'\t'}"
        SLUG="$(printf '%s' "$AGENT" | tr ' /' '__')"
        printf '{"agent":"%s","state":"%s","detail":"%s","cwd":"%s","time":%s}\n' \
          "$AGENT" "$STATE" "$DETAIL" "$CWD" "$(date +%s)" > "$DIR/$SLUG.json"
        """#
        try? script.write(to: p, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: p.path)
    }

    /// 给用户复制的 Claude Code hook 配置（贴进 ~/.claude/settings.json）
    static func claudeHookJSON() -> String {
        let p = scriptPath.path
        return """
        {
          "hooks": {
            "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "'\(p)' working" }] }],
            "Notification": [{ "hooks": [{ "type": "command", "command": "'\(p)' attention" }] }],
            "Stop": [{ "hooks": [{ "type": "command", "command": "'\(p)' done" }] }]
          }
        }
        """
    }
}
