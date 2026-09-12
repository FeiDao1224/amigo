import AppKit

/// 两套主动冒泡：陪伴撒娇，以及可选的久坐/熬夜督促。
/// 防打扰：只在你在电脑前时冒泡；全局最短间隔；各规则自己冷却。
@MainActor
final class BehaviorEngine {
    private let runtime: PetRuntime
    var isEnabled: () -> Bool = { true }
    var isCompanionEnabled: () -> Bool = { true }   // 隐身以外都记账：心情、亲密度
    var isCompanionChat: () -> Bool = { true }      // 才主动冒一句
    var isPetVisible: () -> Bool = { true }
    var onCompanionTick: ((_ idleSeconds: Double, _ returned: Bool) -> String?)?

    private var timer: Timer?
    private var activeMinutes = 0.0
    private var lastProactive = Date.distantPast
    private var lastFired: [String: Date] = [:]
    private var wasAway = false

    init(runtime: PetRuntime) { self.runtime = runtime }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let enabled = isEnabled()
        let tracking = isCompanionEnabled()
        let chatOn = isCompanionChat()
        if !enabled && !tracking { activeMinutes = 0; wasAway = false; return }
        let idle = SystemInfo.idleSeconds()
        if idle < 60 { activeMinutes += 0.5 }
        if idle > 300 { activeMinutes = 0; wasAway = true }

        if tracking {
            _ = onCompanionTick?(idle, false)
        }

        guard isPetVisible(), idle < 60 else { return }
        guard Date().timeIntervalSince(lastProactive) > 18 * 60 else { return }

        if wasAway {
            wasAway = false
            if chatOn, let line = onCompanionTick?(idle, true), !line.isEmpty {
                lastProactive = Date()
                runtime.showBubble(line)
                return
            }
            if enabled {
                fire("back", situation: "主人刚从离开中回到电脑前", fallback: "哟，回来啦～", 30)
            }
            return
        }

        if chatOn, Date().timeIntervalSince(lastFired["murmur"] ?? .distantPast) > 22 * 60 {
            lastFired["murmur"] = Date()
            lastProactive = Date()
            runtime.showBubble(CompanionPolicy.murmur(runtime.mood))
            return
        }

        guard enabled else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 23 || hour < 5 {
            fire("late", situation: "已经深夜 \(hour) 点了，主人还在用电脑", fallback: "都这点了还不睡？我先困了……", 60); return
        }
        if activeMinutes >= 90 {
            fire("sit", situation: "主人已经连续久坐一个半小时", fallback: "又坐一个半小时了，起来走两步吧。", 60); return
        }
        if activeMinutes >= 45 {
            fire("focus", situation: "主人已经专注工作 45 分钟", fallback: "专注 45 分钟啦，来杯咖啡还是喝口水？", 45); return
        }
    }

    private func fire(_ id: String, situation: String, fallback: String, _ cooldownMin: Double) {
        if let last = lastFired[id], Date().timeIntervalSince(last) < cooldownMin * 60 { return }
        lastFired[id] = Date()
        lastProactive = Date()
        runtime.nudge(situation: situation, fallback: fallback)
    }
}
