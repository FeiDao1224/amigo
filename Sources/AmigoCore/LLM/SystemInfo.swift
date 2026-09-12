import AppKit

/// 实时系统状态：注入进宠物的 system prompt，让它知道时间 / 内存 / 你在用什么 app。
enum SystemInfo {
    private static let df: DateFormatter = {
        let d = DateFormatter(); d.locale = Locale(identifier: "zh_CN")
        d.dateFormat = "yyyy年M月d日 EEEE HH:mm"; return d
    }()

    static func context(includeFrontApp: Bool = true) -> String {
        var parts = ["现在是 \(df.string(from: Date()))"]
        if let m = memoryUsedPercent() { parts.append("内存占用约 \(m)%") }
        if includeFrontApp, let app = frontApp() { parts.append("主人正在用「\(app)」") }
        return "【实时状态，需要时自然引用，别生硬报数】" + parts.joined(separator: "；") + "。"
    }

    /// 当前前台 app 名（排除桌面/自己）
    static func frontApp() -> String? {
        guard let f = NSWorkspace.shared.frontmostApplication,
              f.processIdentifier != NSRunningApplication.current.processIdentifier,
              f.bundleIdentifier != "com.apple.finder" else { return nil }
        return f.localizedName
    }

    /// 键鼠空闲秒数。桌宠动作与主动催促共用，避免两处各写一份。
    static func idleSeconds() -> Double {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    static func memoryUsedPercent() -> Int? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        return max(0, min(100, Int((used / total * 100).rounded())))
    }
}
