import AppKit

/// 让宠物待在「你正在操作的那个窗口」**外侧**，不遮挡窗口内容。
///
/// 只读 CGWindowList 拿窗口边框——**不需要辅助功能权限**，装完即用。
/// 位置直接跳过去，不做移动动画：窗口一切换就该已经在位，中间的行走过程只会让人等。
@MainActor
final class WindowFollower {
    /// 宠物和窗口边框之间留的缝
    private let gap: CGFloat = 8
    /// 没有窗口可贴时，离屏幕边缘留的边距
    private let screenInset: CGFloat = 16
    /// 窗口边框查询限流：20fps 每帧都枚举全部窗口太费；拖窗口时 10Hz 跟得上
    private let probeInterval: TimeInterval = 0.1

    /// 这一帧宠物该在哪
    enum Placement {
        case at(CGPoint)   // 宠物底边中点（Cocoa 坐标）
        case hidden        // 全屏，或四周都塞不下 → 藏起来
        case leaveAlone    // 前台是 Amigo 自己，或刚被手动拖走 → 别动它
    }

    private var lastProbe: TimeInterval = 0
    private var cached: Placement = .leaveAlone
    private var currentKey: String?
    /// 被拖走时贴的那个目标：只要还停在它上面就不跟，切到别的窗口自动恢复
    private var detachedKey: String?

    // MARK: 对外

    /// 手动拖走 → 这一次不跟了，等切窗口再归位
    func detachFromCurrent() { detachedKey = currentKey ?? frontTarget().key }

    func placement() -> Placement {
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastProbe > probeInterval {
            lastProbe = now
            cached = resolve()
        }
        return cached
    }

    /// 让下一帧立刻重算（切换 app 时调，省掉限流带来的延迟）
    func invalidate() { lastProbe = 0 }

    // MARK: 内部

    private func resolve() -> Placement {
        let target = frontTarget()
        if let key = target.key, let d = detachedKey, d != key { detachedKey = nil }
        currentKey = target.key
        guard detachedKey == nil else { return .leaveAlone }

        switch target {
        case .ignore:                return .leaveAlone
        case .desktop(_, let point): return .at(point)
        case .window(_, let rect):   return place(besides: rect)
        }
    }

    /// 摆在窗口外侧：右 → 左 → 上，都塞不下就藏起来
    private func place(besides rect: CGRect) -> Placement {
        guard let screen = screen(containing: CGPoint(x: rect.midX, y: rect.midY)) else { return .hidden }
        guard !isFullScreen(rect, on: screen) else { return .hidden }   // 全屏窗口直接藏

        let vf = screen.visibleFrame
        let w = PetLayout.sprite.width, h = PetLayout.sprite.height, half = w / 2

        // 竖直位置：脚跟窗口底边齐平（像站在同一条地面线上），再夹进可视区
        let y = min(max(rect.minY, vf.minY), vf.maxY - h)

        if vf.maxX - rect.maxX >= w + gap {          // 右侧
            return .at(CGPoint(x: rect.maxX + gap + half, y: y))
        }
        if rect.minX - vf.minX >= w + gap {          // 左侧
            return .at(CGPoint(x: rect.minX - gap - half, y: y))
        }
        if vf.maxY - rect.maxY >= h + gap {          // 上方：靠窗口右端站着
            let x = min(max(rect.maxX - half, vf.minX + half), vf.maxX - half)
            return .at(CGPoint(x: x, y: rect.maxY + gap))
        }
        return .hidden                                // 四周都不够
    }

    /// 铺满整块屏（连菜单栏都盖住）就是全屏
    private func isFullScreen(_ rect: CGRect, on screen: NSScreen) -> Bool {
        abs(rect.width - screen.frame.width) < 2 && abs(rect.height - screen.frame.height) < 2
    }

    private enum FrontTarget {
        case window(key: String, rect: CGRect)
        case desktop(key: String, point: CGPoint)
        case ignore

        var key: String? {
            switch self {
            case .window(let k, _), .desktop(let k, _): return k
            case .ignore: return nil
            }
        }
    }

    /// 你「正在操作」的那个窗口。
    ///
    /// 判据是**全局 z 序最上面的普通窗口属不属于前台 app**，而不是「前台 app 有没有窗口」——
    /// 点桌面时 Finder 会变成前台，但它的窗口还压在别人下面，那不该被当成你在操作的窗口。
    private func frontTarget() -> FrontTarget {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .ignore }
        guard app.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return .ignore   // 自己的设置窗 / 聊天窗不贴，也别因此跑去角落
        }
        // 没有任何普通窗口，或最上层那个不属于前台 app（= 你点的是桌面）→ 回落到屏幕角落。
        // 桌面背景板本身已被 excludeDesktopElements 滤掉，不会混进来；
        // 这里也不能按「尺寸等于屏幕」判桌面——那正是全屏窗口的特征，会把全屏误判成桌面。
        guard let top = topmostWindow(), top.pid == app.processIdentifier else {
            return desktopTarget()
        }
        return .window(key: "\(top.pid):\(top.num)", rect: top.rect)
    }

    /// 全局 z 序最上面的那个普通窗口（列表本身就是 z 序，先命中的即最上层）
    private func topmostWindow() -> (pid: pid_t, num: Int, rect: CGRect)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,          // 0 = 普通窗口，滤掉浮层 / 菜单 / 桌宠自己
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let num = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width > 200, height > 120                            // 滤掉工具条、取色器一类小面板
            else { continue }
            return (pid, num, Self.toCocoa(x: x, y: y, width: width, height: height))
        }
        return nil
    }


    /// 没有窗口可贴时的落点：鼠标所在那块屏的右下角
    private func desktopTarget() -> FrontTarget {
        let mouse = NSEvent.mouseLocation
        let idx = NSScreen.screens.firstIndex { $0.frame.contains(mouse) } ?? 0
        guard NSScreen.screens.indices.contains(idx) else { return .ignore }
        let vf = NSScreen.screens[idx].visibleFrame
        let p = CGPoint(x: vf.maxX - screenInset - PetLayout.sprite.width / 2, y: vf.minY + screenInset)
        return .desktop(key: "desktop:\(idx)", point: p)
    }

    /// CGWindow 用主屏左上角原点、y 向下；AppKit 用主屏左下角原点、y 向上
    private static func toCocoa(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: x, y: primaryTop - y - height, width: width, height: height)
    }

    /// 含这个点的屏；都不含就取离它最近的那块（窗口被拖到屏幕外时不至于没有参照）
    private func screen(containing p: CGPoint) -> NSScreen? {
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(p) }) { return hit }
        return NSScreen.screens.min { distance(from: p, to: $0.frame) < distance(from: p, to: $1.frame) }
    }

    private func distance(from p: CGPoint, to r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}
