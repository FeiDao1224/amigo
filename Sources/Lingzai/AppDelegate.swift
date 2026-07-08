import AppKit
import SwiftUI

/// 可成为 key 的宠物面板（否则下方输入框打不了字）
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var petPanel: NSPanel!
    private var settingsWindow: NSWindow?
    private var cursorTimer: Timer?
    private var dragOffset: CGSize?              // 拖动：绝对鼠标坐标锚点
    private var lastDragPos: NSPoint?            // 拖动测速
    private var lastDragTime: TimeInterval?
    private var dragSpeed: CGFloat = 0           // 平滑后的拖动速度 pt/s
    private var rightClickMonitor: Any?          // 右键按配置派发
    private let state = AppState()
    private let runtime = PetRuntime()
    private let chat = ChatSession()
    private var chatWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var engine: BehaviorEngine?
    private var agentBridge: AgentBridge?
    private var focusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PetImages.installDefaults()   // 首启：内置默认形象拷到本机（新用户不空白）
        NSApp.setActivationPolicy(state.config.dockVisible ? .regular : .accessory)
        setupMainMenu()   // 让 Cmd+C/V/X/A 在文本框里生效

        runtime.activeProvider = { [weak state] in state?.activeProvider() }
        runtime.activeCard = { [weak state] in state?.currentCard() ?? .default }
        runtime.memoryContext = { [weak state] in state?.memoryContext() ?? "" }
        SpriteGen.migrateFlat(to: state.config.character)   // 旧扁平动画 → 归到当前形象名下
        runtime.setCharacter(state.config.character)
        state.onGeneratedFramesChanged = { [weak self] in self?.runtime.invalidateActions() }
        state.onCharacterChanged = { [weak self] id in
            PetImages.clearCache()
            self?.runtime.setCharacter(id)
        }
        runtime.speaker = Speaker()
        runtime.shouldReadAloud = { [weak state] in state?.config.readAloud ?? false }
        runtime.nudgeUseLLM = { [weak state] in state?.config.proactiveLLM ?? false }

        chat.provider = { [weak state] in state?.activeProvider() }
        chat.systemPrompt = { [weak state] in
            guard let s = state else { return "" }
            let base = s.currentCard().systemPrompt
            let mem = s.memoryContext()
            let sys = SystemInfo.context()
            return [base, mem, sys].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        chat.onReply = { [weak self] r in
            self?.runtime.waitingReply = false
            self?.runtime.showBubble(r)
        }
        chat.onInferred = { [weak state] items in state?.addInferred(items) }
        chat.isStealth = { [weak state] in state?.config.stealth ?? false }

        state.onStartFocus = { [weak self] title in self?.startFocus(title) }
        state.onTaskDone = { [weak self] title in self?.runtime.showBubble("搞定《\(title)》！你今天是真的推进了 👏") }

        setupStatusItem()
        setupPetPanel()
        setupRightClick()
        startCursorTracking()
        maybeMorningGreeting()
        // 启动就冒个云气泡，让你立刻看到新气泡 + 知道长按能说话
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.runtime.showBubble(self.state.entitled ? "长按我，就能跟我说话～"
                : "试用已到期，去 设置→关于 激活就能继续用～")
        }
        Task { await state.revalidate() }   // 启动向激活服务器复验（可吊销/到期）

        let e = BehaviorEngine(runtime: runtime)
        e.isEnabled = { [weak self] in (self?.state.entitled ?? false) && (self?.state.config.proactive ?? false) && !(self?.state.config.stealth ?? false) && !(self?.state.focusing ?? false) }
        e.isPetVisible = { [weak self] in self?.petPanel?.isVisible ?? false }
        e.start()
        engine = e

        let ab = AgentBridge(runtime: runtime)
        ab.isEnabled = { [weak self] in (self?.state.config.agentMonitor ?? false) && (self?.state.entitled ?? false) }
        ab.start()
        agentBridge = ab

        if !state.config.onboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showOnboarding() }
        }
    }

    // 深链导入（打包成 .app 后，点击 lingzai:// / 中转站分享链接会走这里）
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { _ = state.importProvider(from: u.absoluteString) }
        openSettings()
    }

    // MARK: 主菜单（编辑菜单 → 复制/粘贴快捷键在文本框生效）
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "隐藏 Amigo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Amigo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: Selector(("cut:")), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: Selector(("copy:")), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: Selector(("paste:")), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = edit

        NSApp.mainMenu = main
    }

    // MARK: 状态栏
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Amigo")
        let menu = NSMenu()
        let chatItem = NSMenuItem(title: "和阿豆聊聊…", action: #selector(openChat), keyEquivalent: "")
        let open = NSMenuItem(title: "打开设置…", action: #selector(openSettings), keyEquivalent: ",")
        let toggle = NSMenuItem(title: "显示 / 隐藏宠物", action: #selector(togglePet), keyEquivalent: "")
        let quit = NSMenuItem(title: "退出 Amigo", action: #selector(quitApp), keyEquivalent: "q")
        for it in [chatItem, open, toggle, quit] { it.target = self }
        menu.addItem(chatItem); menu.addItem(open); menu.addItem(toggle); menu.addItem(.separator()); menu.addItem(quit)
        statusItem.menu = menu
    }

    // MARK: 宠物窗
    private func setupPetPanel() {
        let size = NSSize(width: 260, height: 320)
        let panel = PetPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PetView(
            rt: runtime,
            onDrag: { [weak self] ended in self?.dragTick(ended: ended) },
            onFile: { [weak self] url in self?.runtime.handleFile(url) },
            onSend: { [weak self] text in
                guard let self else { return }
                self.runtime.chatting = false            // 收起输入框
                self.runtime.waitingReply = true         // 进入"打电话"等回复
                self.runtime.showBubble("…", sticky: true)
                self.chat.send(text)
            },
            onTrigger: { [weak self] t in self?.dispatchClick(t) }
        )
        panel.contentView = NSHostingView(rootView: view)

        if let o = state.petOrigin() {
            panel.setFrameOrigin(o)
        } else if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 20, y: vf.minY + 10))
        }
        panel.orderFrontRegardless()
        petPanel = panel
    }

    // MARK: 眼睛跟随全屏鼠标
    private func startCursorTracking() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.cursorTick() }
        }
    }

    private func cursorTick() {
        guard let panel = petPanel else { return }
        let frame = panel.frame
        let mouse = NSEvent.mouseLocation

        // 点击穿透：鼠标落在宠物身上（或正在拖动/对话）才接收点击，其余透传到桌面。
        // 抓取区放宽 + 滞回（进入用紧区、离开用宽区），既好抓又不会在边缘反复抖动导致拖动抓不住。
        let interactive = !panel.ignoresMouseEvents
        let grab = petGrabRect(frame, expand: interactive ? 46 : 0)   // 已在交互态→用更大的宽区留边
        let wantIgnore = (runtime.chatting || dragOffset != nil) ? false : !grab.contains(mouse)
        if panel.ignoresMouseEvents != wantIgnore { panel.ignoresMouseEvents = wantIgnore }   // 只在变化时设，省窗口服务器开销

        updateBehaviorAction()
    }

    /// 宠物可抓取区域：面板底部居中（猫身 92×140 + 上方气泡余量），比可见猫身宽松一圈，好抓。
    private func petGrabRect(_ frame: NSRect, expand: CGFloat) -> CGRect {
        let w: CGFloat = 150, h: CGFloat = 210
        return CGRect(x: frame.midX - w / 2 - expand, y: frame.minY + 2 - expand,
                      width: w + expand * 2, height: h + expand * 2)
    }

    // 行为驱动：对话/等回复→打电话；拖动→走/跑(带方向)；用电脑→工作；桌面空→待着
    private func updateBehaviorAction() {
        if let until = runtime.oneShotUntil {                // 点击触发的一次性动作优先
            if Date() < until { runtime.showAction(runtime.oneShotKey); return }
            runtime.oneShotUntil = nil
        }
        if runtime.waitingReply || runtime.chatting {
            runtime.facingLeft = false
            runtime.showAction(state.config.mapChat); return
        }
        guard state.config.behaviorDriven else {
            runtime.facingLeft = false; runtime.showAction(state.config.activeAction); return
        }
        if dragOffset != nil {
            let fast = dragSpeed > 320
            runtime.showAction(fast ? state.config.mapFast : state.config.mapSlow, fallbackMotion: fast ? 2 : 1)
        } else {
            runtime.facingLeft = false
            let now = Date().timeIntervalSinceReferenceDate
            if now - lastFrontCheck > 0.5 { frontActive = SystemInfo.frontApp() != nil; lastFrontCheck = now }
            runtime.showAction(frontActive ? "work" : state.config.activeAction)   // 用电脑→工作 / 桌面空→默认
        }
    }
    private var frontActive = false
    private var lastFrontCheck: TimeInterval = 0

    // MARK: 拖动（绝对坐标，无反馈抖动）
    private func dragTick(ended: Bool) {
        guard let panel = petPanel else { return }
        let m = NSEvent.mouseLocation
        if dragOffset == nil {
            dragOffset = CGSize(width: m.x - panel.frame.origin.x, height: m.y - panel.frame.origin.y)
        }
        let off = dragOffset!
        panel.setFrameOrigin(NSPoint(x: m.x - off.width, y: m.y - off.height))
        // 拖动速度（平滑）→ 区分走/跑
        let now = Date().timeIntervalSinceReferenceDate
        if let lp = lastDragPos, let lt = lastDragTime, now > lt {
            let dx = m.x - lp.x
            let inst = hypot(dx, m.y - lp.y) / CGFloat(now - lt)
            dragSpeed = dragSpeed * 0.6 + inst * 0.4
            if abs(dx) > 0.6 { runtime.facingLeft = dx < 0 }   // 往左拖 → 朝左走
        }
        lastDragPos = m; lastDragTime = now
        runtime.setState(ended ? .idle : .dragged)
        if ended {
            dragOffset = nil; lastDragPos = nil; lastDragTime = nil; dragSpeed = 0
            state.setPetPosition(panel.frame.origin)
        }
    }

    // 右键按配置派发（可在设置→交互里改）
    private func setupRightClick() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let panel = self.petPanel, panel.isVisible, event.window === panel else { return event }
            self.dispatchClick("right")
            return nil
        }
    }

    // 交互派发：把某触发映射到配置里的行为
    private func dispatchClick(_ trigger: String) {
        switch trigger {
        case "left":   executeClick(state.config.clickLeft)
        case "double": executeClick(state.config.clickDouble)
        case "long":   executeClick(state.config.clickLong)
        case "right":  executeClick(state.config.clickRight)
        default: break
        }
    }
    private func executeClick(_ key: String) {
        if !state.entitled && key != "settings" && key != "menu" {
            runtime.showBubble("试用到期啦，去 设置→关于 激活就能继续用～")
            return
        }
        switch key {
        case "", "none": break
        case "speak":    runtime.speak()
        case "chat":     startInlineChat()
        case "settings": openSettings()
        case "hide":     togglePet()
        case "menu":     showPetMenu()
        default:         if key.hasPrefix("act:") { runtime.oneShot(String(key.dropFirst(4))) }
        }
    }
    private func showPetMenu() {
        let menu = NSMenu()
        let speak = NSMenuItem(title: "摸摸头", action: #selector(menuSpeak), keyEquivalent: "")
        let settings = NSMenuItem(title: "打开设置…", action: #selector(openSettings), keyEquivalent: "")
        let hide = NSMenuItem(title: "隐藏宠物", action: #selector(togglePet), keyEquivalent: "")
        let quit = NSMenuItem(title: "退出 Amigo", action: #selector(quitApp), keyEquivalent: "")
        for it in [speak, settings, hide, quit] { it.target = self }
        menu.items = [speak, settings, hide, .separator(), quit]
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    @objc private func menuSpeak() { runtime.speak() }

    // 点宠物：在它下方开/关输入框（不再开聊天窗）
    private func startInlineChat() {
        if runtime.chatting { runtime.chatting = false; return }
        runtime.chatting = true
        petPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 晨间彩蛋
    private func maybeMorningGreeting() {
        let hour = Calendar.current.component(.hour, from: Date())
        guard (5...10).contains(hour) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.runtime.morningGreeting()
        }
    }

    // MARK: 设置窗（毛玻璃）
    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Amigo · 设置"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isMovableByWindowBackground = true
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: SettingsView(state: state))
            settingsWindow = w
        }
        NSApp.setActivationPolicy(.regular)   // 临时切正常 App：真菜单栏，粘贴生效
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 首启引导窗
    private func showOnboarding() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false; w.delegate = self
        let view = OnboardingView(
            onConfigureModel: { [weak self] in self?.state.markOnboarded(); self?.onboardingWindow?.close(); self?.openSettings() },
            onDone: { [weak self] in self?.state.markOnboarded(); self?.onboardingWindow?.close() }
        )
        let host = NSHostingView(rootView: view)
        w.contentView = host
        w.setContentSize(host.fittingSize)
        w.center()
        onboardingWindow = w
        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 关掉设置/聊天/引导窗 → 切回菜单栏模式（尊重 Dock 显示设置）
    func windowWillClose(_ notification: Notification) {
        let w = notification.object as? NSWindow
        guard w === settingsWindow || w === chatWindow || w === onboardingWindow else { return }
        NSApp.setActivationPolicy(state.config.dockVisible ? .regular : .accessory)
    }

    @objc private func openChat() {
        if chatWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "和阿豆聊聊"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: ChatView(session: chat))
            if let screen = NSScreen.main {
                let vf = screen.visibleFrame
                w.setFrameOrigin(NSPoint(x: vf.maxX - 410, y: vf.minY + 60))
            }
            chatWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        chatWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 陪做模式：安静陪你 25 分钟，期间不打扰，到点问一句
    private func startFocus(_ title: String) {
        state.focusing = true
        runtime.showBubble("好，陪你做《\(title)》—— 25 分钟，我在，专注就好。")
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 25 * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.state.focusing = false
                self?.runtime.showBubble("25 分钟到啦，《\(title)》推进得咋样？继续、歇会儿，还是我帮你理理刚才的？")
            }
        }
    }

    @objc private func togglePet() {
        guard let panel = petPanel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}
