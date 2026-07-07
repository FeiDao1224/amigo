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
    private let state = AppState()
    private let runtime = PetRuntime()
    private let chat = ChatSession()
    private var chatWindow: NSWindow?
    private var engine: BehaviorEngine?
    private var focusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(state.config.dockVisible ? .regular : .accessory)
        setupMainMenu()   // 让 Cmd+C/V/X/A 在文本框里生效

        runtime.activeProvider = { [weak state] in state?.activeProvider() }
        runtime.activeCard = { [weak state] in state?.currentCard() ?? .default }
        runtime.memoryContext = { [weak state] in state?.memoryContext() ?? "" }
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
            return mem.isEmpty ? base : base + "\n\n" + mem
        }
        chat.onReply = { [weak self] r in self?.runtime.showBubble(r) }
        chat.onInferred = { [weak state] items in state?.addInferred(items) }
        chat.isStealth = { [weak state] in state?.config.stealth ?? false }

        state.onStartFocus = { [weak self] title in self?.startFocus(title) }
        state.onTaskDone = { [weak self] title in self?.runtime.showBubble("搞定《\(title)》！你今天是真的推进了 👏") }

        setupStatusItem()
        setupPetPanel()
        startCursorTracking()
        maybeMorningGreeting()

        let e = BehaviorEngine(runtime: runtime)
        e.isEnabled = { [weak self] in (self?.state.config.proactive ?? false) && !(self?.state.config.stealth ?? false) && !(self?.state.focusing ?? false) }
        e.isPetVisible = { [weak self] in self?.petPanel?.isVisible ?? false }
        e.start()
        engine = e
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
        appMenu.addItem(withTitle: "隐藏灵崽", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出灵崽", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "灵崽")
        let menu = NSMenu()
        let chatItem = NSMenuItem(title: "和阿豆聊聊…", action: #selector(openChat), keyEquivalent: "")
        let open = NSMenuItem(title: "打开设置…", action: #selector(openSettings), keyEquivalent: ",")
        let toggle = NSMenuItem(title: "显示 / 隐藏宠物", action: #selector(togglePet), keyEquivalent: "")
        let quit = NSMenuItem(title: "退出灵崽", action: #selector(quitApp), keyEquivalent: "q")
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
            onSpeak: { [weak self] in self?.runtime.speak() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onTogglePet: { [weak self] in self?.togglePet() },
            onQuit: { NSApp.terminate(nil) },
            onDrag: { [weak self] ended in self?.dragTick(ended: ended) },
            onCoffee: { [weak self] in self?.runtime.feedCoffee() },
            onWater: { [weak self] in self?.runtime.feedWater() },
            onFile: { [weak self] url in self?.runtime.handleFile(url) },
            onChat: { [weak self] in self?.startInlineChat() },
            onSend: { [weak self] text in self?.chat.send(text) }
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
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.cursorTick() }
        }
    }

    private func cursorTick() {
        guard let panel = petPanel else { return }
        let frame = panel.frame
        let mouse = NSEvent.mouseLocation

        // 点击穿透：只有鼠标落在猫身上（或正在拖动）才接收点击，其余透传到桌面
        let catRect = CGRect(x: frame.midX - 60, y: frame.minY + 6, width: 120, height: 160)
        panel.ignoresMouseEvents = (runtime.chatting || dragOffset != nil) ? false : !catRect.contains(mouse)

        // 眼睛跟随
        if state.config.eyesFollow {
            let center = CGPoint(x: frame.midX, y: frame.minY + 120)   // 猫头大致位置
            let scale: CGFloat = 240
            let ex = max(-1, min(1, (mouse.x - center.x) / scale))
            let ey = max(-1, min(1, (mouse.y - center.y) / scale))
            runtime.eyeVector = CGSize(width: ex, height: -ey)     // SwiftUI y 向下
        } else if runtime.eyeVector != .zero {
            runtime.eyeVector = .zero
        }

        updateBehaviorAction()
    }

    // 行为驱动：按交互状态切动作（对话→打电话 / 快拖→跑 / 慢拖→走 / 空闲→待着）
    private func updateBehaviorAction() {
        guard state.config.behaviorDriven else { runtime.showAction(state.config.activeAction); return }
        if runtime.chatting { runtime.showAction(state.config.mapChat); return }
        if dragOffset != nil {
            let fast = dragSpeed > 320
            runtime.showAction(fast ? state.config.mapFast : state.config.mapSlow, fallbackMotion: fast ? 2 : 1)
        } else {
            runtime.showAction(state.config.mapIdle)
        }
    }

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
            let inst = hypot(m.x - lp.x, m.y - lp.y) / CGFloat(now - lt)
            dragSpeed = dragSpeed * 0.6 + inst * 0.4
        }
        lastDragPos = m; lastDragTime = now
        runtime.setState(ended ? .idle : .dragged)
        if ended {
            dragOffset = nil; lastDragPos = nil; lastDragTime = nil; dragSpeed = 0
            state.setPetPosition(panel.frame.origin)
        }
    }

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
            w.title = "灵崽 · 设置"
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

    // 关掉设置/聊天窗 → 切回菜单栏模式（尊重 Dock 显示设置）
    func windowWillClose(_ notification: Notification) {
        let w = notification.object as? NSWindow
        guard w === settingsWindow || w === chatWindow else { return }
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
