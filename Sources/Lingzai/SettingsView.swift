import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct NavItem: Identifiable {
    let key, title, subtitle, icon: String
    let color: Color
    var id: String { key }
}

// AI 动作：网格卡片（预览 + 生成/重生成 + 设为当前）
private struct ActionRow: View {
    @ObservedObject var state: AppState
    let action: PetAnimAction
    private var status: String { state.actionStatus[action.rawValue] ?? "" }
    private var character: String { state.config.character }
    private var made: Bool { SpriteGen.exists(character: character, action: action.rawValue) }
    private var isCurrent: Bool { state.config.activeAction == action.rawValue }

    var body: some View {
        VStack(spacing: 6) {
            ActionPreview(character: character, action: action).id("\(character)-\(status)")
                .frame(maxWidth: .infinity).frame(height: 72)
            Text("\(action.emoji) \(action.title)").font(.system(size: 12, weight: .medium))
            statusText
            Button(status == "generating" ? "生成中" : (made ? "重生成" : "生成")) {
                Task { await state.generateAction(action) }
            }.controlSize(.mini).buttonStyle(.borderedProminent).disabled(status == "generating")
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { state.setActiveAction(action.rawValue) }
    }
    @ViewBuilder private var statusText: some View {
        if status == "generating" { Text("生成中…").font(.caption2).foregroundStyle(.secondary) }
        else if status.hasPrefix("failed:") { Text(String(status.dropFirst(7))).font(.caption2).foregroundStyle(.red).lineLimit(2) }
        else if made { Text(isCurrent ? "当前播放" : "已生成").font(.caption2).foregroundStyle(.green) }
        else { Text("未生成").font(.caption2).foregroundStyle(.secondary) }
    }
}

// AI 动作预览：循环播放该形象该动作的帧
private struct ActionPreview: View {
    let character: String
    let action: PetAnimAction
    @State private var frames: [NSImage] = []
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05))
            if frames.isEmpty {
                Image(systemName: "sparkles").foregroundStyle(.secondary)
            } else {
                TimelineView(.animation) { tl in
                    let i = Int(tl.date.timeIntervalSinceReferenceDate * action.fps) % frames.count
                    Image(nsImage: frames[i]).resizable().interpolation(.none).scaledToFit().padding(4)
                }
            }
        }
        .onAppear { frames = SpriteGen.loadFrames(character: character, action: action.rawValue) }
    }
}

// 形象卡片：悬停时光斑跟随鼠标 + 彩色发光描边 + 抬升
private struct CharacterCard: View {
    let id: String
    let name: String
    let selected: Bool
    let onTap: () -> Void
    @State private var hover: CGPoint?
    private let w: CGFloat = 92, h: CGFloat = 116

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let img = PetImages.image(id) {
                    Image(nsImage: img).resizable().interpolation(.none).scaledToFit().padding(8)
                } else {
                    Image(systemName: "pawprint.fill").font(.title).foregroundStyle(.orange)
                }
            }
            .frame(width: 74, height: 82)
            Text(name).font(.system(size: 11, weight: selected ? .semibold : .regular))
        }
        .frame(width: w, height: h)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05))
                if let p = hover {
                    RadialGradient(colors: [Color.accentColor.opacity(0.38), .clear],
                                   center: UnitPoint(x: p.x / w, y: p.y / h), startRadius: 2, endRadius: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14).strokeBorder(
                selected ? AnyShapeStyle(Color.accentColor)
                    : (hover != nil
                        ? AnyShapeStyle(AngularGradient(colors: [.blue, .purple, .pink, .orange, .blue], center: .center))
                        : AnyShapeStyle(Color.white.opacity(0.08))),
                lineWidth: selected || hover != nil ? 2 : 1)
        )
        .scaleEffect(hover != nil ? 1.05 : 1)
        .shadow(color: .black.opacity(hover != nil ? 0.18 : 0), radius: 8, y: 4)
        .animation(.easeOut(duration: 0.18), value: hover != nil)
        .animation(.easeOut(duration: 0.18), value: selected)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onContinuousHover { phase in
            switch phase { case .active(let p): hover = p; case .ended: hover = nil }
        }
        .onTapGesture { onTap() }
    }
}

private struct CharacterPicker: View {
    @ObservedObject var state: AppState
    private var chars: [(String, String)] {
        var a: [(String, String)] = []
        if FileManager.default.fileExists(atPath: PetImages.dir.appendingPathComponent("custom.png").path) {
            a.append(("custom", "我的形象"))          // 自定义形象置顶
        }
        a += [("cat", "默认小猫"), ("lazy_fish", "摸鱼鱼"), ("anxious_fish", "看表鱼"), ("shocked_fish", "震惊鱼")]
        return a
    }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chars, id: \.0) { it in
                    CharacterCard(id: it.0, name: it.1, selected: state.config.character == it.0) {
                        state.setCharacter(it.0)
                    }
                }
            }.padding(.horizontal, 2).padding(.vertical, 6)
        }
    }
}

// Pro 激活页：离线邮箱+激活码验签解锁
private struct ProPane: View {
    @ObservedObject var state: AppState
    @State private var email = ""
    @State private var code = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Pro · 解锁全部")
            if state.licensed {
                GroupCard {
                    GRow(title: "已激活 ✓", subtitle: "感谢支持！Pro 已全部解锁（\(state.config.licenseEmail)）") {
                        Button("注销") { state.deactivate(); email = ""; code = ""; failed = false }
                    }
                }
            } else {
                GroupCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("输入购买时用的邮箱和收到的激活码").font(.system(size: 12)).foregroundStyle(.secondary)
                        TextField("邮箱", text: $email).textFieldStyle(.roundedBorder)
                        TextField("激活码", text: $code, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
                        HStack {
                            if failed { Text("邮箱或激活码不对").font(.caption).foregroundStyle(.red) }
                            Spacer()
                            Button("激活") { failed = !state.activate(email: email, code: code) }
                                .buttonStyle(.borderedProminent).disabled(email.isEmpty || code.isEmpty)
                        }
                    }.padding(14)
                }
                GroupCard {
                    GRow(title: "还没有激活码？", subtitle: "购买后用你的邮箱生成，一码解锁全部 Pro 功能") {
                        Text("购买入口待配").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            SectionHeader("Pro 解锁什么")
            GroupCard {
                proRow("自定义形象", "上传任意图，一键像素化成你的专属桌宠")
                RowDivider()
                proRow("更多形象与动作", "陆续解锁")
                RowDivider()
                proRow("AI 督促文案", "更有性格的主动提醒")
            }
            Text("离线激活，无需联网验证；激活码与你的邮箱绑定。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func proRow(_ t: String, _ s: String) -> some View {
        GRow(title: t, subtitle: s) { Image(systemName: "crown.fill").foregroundStyle(.orange).font(.caption) }
    }
}

// 自定义形象：选图 → 像素化预览 → 设为桌宠（Pro）
private struct CustomPetCard: View {
    @ObservedObject var state: AppState
    var onUpgrade: () -> Void = {}
    @State private var source: NSImage?
    @State private var preview: NSImage?
    @State private var level: Double = 0.5
    @State private var flood = false

    private var rows: Int { Int((110 - level * 46).rounded()) }   // 0→110精细 .. 1→64块状
    private var levels: Int { level > 0.6 ? 4 : 5 }

    var body: some View {
        GroupCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06))
                        if let p = preview {
                            Image(nsImage: p).resizable().interpolation(.none).scaledToFit().padding(6)
                        } else {
                            VStack(spacing: 5) {
                                Image(systemName: "photo.badge.plus").font(.title2).foregroundStyle(.secondary)
                                Text("选张图\n变像素桌宠").font(.system(size: 10))
                                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 96, height: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("自定义形象").font(.system(size: 13, weight: .semibold))
                        Text("选一张图（自拍 / 喜欢的角色 / 表情包），自动像素化成你的专属桌宠。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { pick() } label: { Label("选择图片…", systemImage: "photo.on.rectangle") }
                    }
                    Spacer(minLength: 0)
                }

                if source != nil {
                    HStack(spacing: 12) {
                        Text("像素程度").font(.system(size: 11)).foregroundStyle(.secondary)
                        Slider(value: $level, in: 0...1) { editing in if !editing { rebuild() } }
                        Toggle("去白底", isOn: $flood).toggleStyle(.checkbox)
                            .font(.system(size: 11)).onChange(of: flood) { _ in rebuild() }
                    }
                    HStack {
                        Text("像素化在本机完成，图片不会上传。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        if state.licensed {
                            Button("设为桌宠") {
                                if let s = source { state.setCustomPet(from: s, rows: rows, levels: levels, flood: flood) }
                            }
                            .buttonStyle(.borderedProminent).disabled(preview == nil)
                        } else {
                            Button { onUpgrade() } label: { Label("Pro 解锁", systemImage: "crown.fill") }
                                .buttonStyle(.borderedProminent).tint(.orange)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func rebuild() {
        guard let s = source else { return }
        preview = Pixelizer.pixelize(s, rows: rows, levels: levels, scale: 3, flood: flood)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            source = img
            rebuild()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var sel = "model"

    private let items: [NavItem] = [
        .init(key: "general", title: "通用",   subtitle: "系统与基础行为",   icon: "gearshape.fill",           color: .gray),
        .init(key: "model",   title: "模型",   subtitle: "接入与中转站",     icon: "cpu",                      color: .blue),
        .init(key: "pet",     title: "宠物",   subtitle: "形象·动作·性格·记忆·语音·交互", icon: "pawprint.fill",  color: .pink),
        .init(key: "task",    title: "任务",   subtitle: "提醒与督促",       icon: "checklist",                color: .orange),
        .init(key: "privacy", title: "隐私",   subtitle: "它懂你·但不偷看你",  icon: "lock.shield.fill",         color: .mint),
        .init(key: "pro",     title: "Pro",   subtitle: "激活 · 解锁全部",    icon: "crown.fill",               color: .orange),
        .init(key: "about",   title: "关于",   subtitle: "版本与更新",       icon: "info.circle.fill",         color: .gray),
    ]

    var body: some View {
        ZStack {
        VisualEffectView().ignoresSafeArea()
        HStack(spacing: 0) {
            // 侧栏
            VStack(spacing: 3) {
                Spacer().frame(height: 24)   // 给红绿灯让位
                ForEach(items) { it in
                    SidebarRow(title: it.title, subtitle: it.subtitle,
                               icon: it.icon, color: it.color, selected: sel == it.key)
                        .onTapGesture { sel = it.key }
                }
                Spacer()
            }
            .frame(width: 208)
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial)

            Divider()

            // 内容
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        }
        .frame(minWidth: 780, minHeight: 540)
    }

    @ViewBuilder private var content: some View {
        switch sel {
        case "general":  general
        case "model":    ModelPane(state: state)
        case "pet":      pet
        case "task":     TaskPane(state: state)
        case "privacy":  privacy
        case "pro":      ProPane(state: state)
        default:         about
        }
    }

    private var dockBinding: Binding<Bool> { Binding(get: { state.config.dockVisible }, set: { state.setDockVisible($0) }) }
    private var eyesBinding: Binding<Bool> { Binding(get: { state.config.eyesFollow }, set: { state.setEyesFollow($0) }) }
    private var proactiveBinding: Binding<Bool> { Binding(get: { state.config.proactive }, set: { state.setProactive($0) }) }
    private var readAloudBinding: Binding<Bool> { Binding(get: { state.config.readAloud }, set: { state.setReadAloud($0) }) }
    private var proactiveLLMBinding: Binding<Bool> { Binding(get: { state.config.proactiveLLM }, set: { state.setProactiveLLM($0) }) }
    private var stealthBinding: Binding<Bool> { Binding(get: { state.config.stealth }, set: { state.setStealth($0) }) }
    private var behaviorBinding: Binding<Bool> { Binding(get: { state.config.behaviorDriven }, set: { state.setBehaviorDriven($0) }) }
    private func mapRow(_ title: String, _ trigger: String, _ current: String) -> some View {
        GRow(title: title) {
            Picker("", selection: Binding(get: { current }, set: { state.setMap(trigger, $0) })) {
                ForEach(PetAnimAction.allCases) { a in Text("\(a.emoji) \(a.title)").tag(a.rawValue) }
            }.labelsHidden().frame(width: 130)
        }
    }

    // MARK: 隐私中心 —— 它懂你，但不偷看你
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("隐私 · 它懂你，但不偷看你")
            GroupCard {
                GRow(title: "数据都在你自己的电脑上",
                     subtitle: "记忆 / 任务 / 性格 / 形象 / API Key 全部只存在本机，从不上传到我们的服务器") {
                    Button("在访达中打开") { state.revealDataFolder() }
                }
            }

            SectionHeader("它到底观察什么")
            GroupCard {
                GRow(title: "只看「你多久没碰键鼠」",
                     subtitle: "为了在合适时候提醒你，它只用系统给的这一个闲置时长。不读窗口内容、不截屏、不记录你打了什么字。") { EmptyView() }
                RowDivider()
                GRow(title: "主动观察与督促", subtitle: "关掉后它完全不看、不主动冒泡") {
                    Toggle("", isOn: proactiveBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "隐身模式", subtitle: "临时全部静默：不观察、不打扰，直到你关掉") {
                    Toggle("", isOn: stealthBinding).labelsHidden().toggleStyle(.switch)
                }
            }

            SectionHeader("发给大模型的内容")
            GroupCard {
                GRow(title: "只在你和你选的模型之间",
                     subtitle: "对话、你让它记住的记忆、你设的性格，会发给你自己配置的大模型来生成回复；API Key 只存本机，数据不经过我们。") { EmptyView() }
            }

            SectionHeader("你的控制权")
            GroupCard {
                GRow(title: "导出我的数据", subtitle: "把记忆 / 任务 复制一份到你选的文件夹（不含 Key）") {
                    Button("导出…") { state.exportData() }
                }
                RowDivider()
                GRow(title: "让它忘记我", subtitle: "清空它记住的关于你的一切（保留模型与性格）") {
                    Button("清空记忆") {
                        if confirm("清空全部记忆？", "它将忘记关于你的一切，无法恢复。") { state.forgetMe() }
                    }
                }
                RowDivider()
                GRow(title: "清空全部数据", subtitle: "记忆 / 任务 / 自定义形象 / 性格全部抹掉（模型 Key 在「模型」页单独管理）") {
                    Button("清空…") {
                        if confirm("清空全部数据？", "记忆、任务、自定义形象、性格都会被删除，无法恢复。") { state.wipeAllData() }
                    }.tint(.red)
                }
            }

            Text("原则：Local-first。它可以很懂你，但你随时能看见、导出、删除它知道的一切。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func confirm(_ title: String, _ msg: String) -> Bool {
        let a = NSAlert()
        a.messageText = title; a.informativeText = msg; a.alertStyle = .warning
        a.addButton(withTitle: "确认"); a.addButton(withTitle: "取消")
        return a.runModal() == .alertFirstButtonReturn
    }

    private var task: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("任务 · 行为督促")
            GroupCard {
                GRow(title: "主动督促", subtitle: "阿豆会根据你的专注 / 久坐 / 作息主动提醒") {
                    Toggle("", isOn: proactiveBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "专注 45 分钟", subtitle: "提醒你喝水或来杯咖啡") { Text("已内置").font(.caption).foregroundStyle(.secondary) }
                RowDivider()
                GRow(title: "久坐 90 分钟", subtitle: "提醒你起来走两步") { Text("已内置").font(.caption).foregroundStyle(.secondary) }
                RowDivider()
                GRow(title: "深夜提醒", subtitle: "23 点后催你睡") { Text("已内置").font(.caption).foregroundStyle(.secondary) }
                RowDivider()
                GRow(title: "督促文案由 AI 生成", subtitle: "更有性格（费一点 token）；关则用内置文案") {
                    Toggle("", isOn: proactiveLLMBinding).labelsHidden().toggleStyle(.switch)
                }
            }
            Text("只在你在电脑前时才冒泡，全局最短间隔 18 分钟，避免打扰。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("通用")
            GroupCard {
                GRow(title: "在 Dock 显示图标", subtitle: "关闭则只驻留在顶部状态栏（推荐）") {
                    Toggle("", isOn: dockBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "语言", subtitle: "默认跟随系统，也可固定为简体中文 / English") {
                    Text("跟随系统").foregroundStyle(.secondary)
                }
                RowDivider()
                GRow(title: "开机自启", subtitle: "登录 macOS 后自动运行灵崽") {
                    Toggle("", isOn: Binding(get: { LaunchAtLogin.isEnabled }, set: { LaunchAtLogin.set($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private var pet: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("宠物")
            GroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("形象").font(.system(size: 13, weight: .medium))
                    Text("选个角色（悬停有光效）；AI 动作按当前形象分别生成与切换")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    CharacterPicker(state: state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
            SectionHeader("自定义形象")
            CustomPetCard(state: state, onUpgrade: { sel = "pro" })

            SectionHeader("动作")
            GroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("用当前形象作参考，AI 生成像素动作帧（直连你在「模型」页配置的服务）。动画按形象分别保存、换形象自动切换。点卡片＝设为默认播放。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(state.batchGenerating ? "生成中…" : "一键生成全部") {
                            Task { await state.generateAllActions() }
                        }.buttonStyle(.borderedProminent).controlSize(.small).disabled(state.batchGenerating)
                        if state.batchGenerating { Text(state.batchProgress).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                    }
                }.padding(14)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(PetAnimAction.allCases) { a in ActionRow(state: state, action: a) }
            }

            PersonaPane(state: state)
            MemoryPane(state: state)
            interact
            voice
        }
    }

    private func modeCard(_ t: String, _ s: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: selected ? "menubar.dock.rectangle" : "macbook")
                .font(.title2).foregroundStyle(selected ? Color.pink : .secondary)
            Text(t).font(.system(size: 13, weight: .semibold))
            Text(s).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.pink : .white.opacity(0.06), lineWidth: selected ? 2 : 1))
    }

    private var voice: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("语音")
            GroupCard {
                GRow(title: "朗读回复", subtitle: "阿豆说话时用系统语音读出来") {
                    Toggle("", isOn: readAloudBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "语音模型", subtitle: "当前用 macOS 系统语音；开源本地音色模型待接入") {
                    Text("系统语音").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var interact: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("交互")
            GroupCard {
                GRow(title: "行为驱动动作", subtitle: "根据你的操作自动切换动作（需先生成对应动作）") {
                    Toggle("", isOn: behaviorBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider(); mapRow("慢速拖动 → ", "slow", state.config.mapSlow)
                RowDivider(); mapRow("快速拖动 → ", "fast", state.config.mapFast)
                RowDivider(); mapRow("对话中 → ", "chat", state.config.mapChat)
                RowDivider()
                GRow(title: "空闲", subtitle: "没操作时播放你在「动作」里选中的默认动作") {
                    Text("＝默认动作").font(.caption).foregroundStyle(.secondary)
                }
                RowDivider()
                GRow(title: "左键点击", subtitle: "戳一下 → 摸头 / 冒一句") { Text("固定").font(.caption).foregroundStyle(.secondary) }
                RowDivider()
                GRow(title: "长按", subtitle: "长按 → 打开对话输入框") { Text("固定").font(.caption).foregroundStyle(.secondary) }
                RowDivider()
                GRow(title: "右键点击", subtitle: "菜单 → 摸头 / 设置 / 隐藏 / 退出") { Text("固定").font(.caption).foregroundStyle(.secondary) }
                RowDivider()
                GRow(title: "拖动", subtitle: "移动宠物位置") { Text("固定").font(.caption).foregroundStyle(.secondary) }
                RowDivider()
                GRow(title: "文件拖动", subtitle: "拖文件到它身上 → 用你的模型帮你看 / 给处理建议") {
                    Text("已开放").font(.caption).foregroundStyle(.green)
                }
            }
            Text("动作没生成时会回退到静态形象 / 程序动画，不影响使用。「新建交互 / 双击映射」下一版加。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("关于")
            GroupCard {
                GRow(title: "灵崽 Lingzai", subtitle: "被你真实行为驱动的桌面搭子") { Text("v0.1 原生内测").foregroundStyle(.secondary) }
            }
        }
    }

    private func placeholder(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title)
            GroupCard {
                GRow(title: "建设中", subtitle: desc) {
                    Image(systemName: "hammer.fill").foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 模型页
struct ModelPane: View {
    @ObservedObject var state: AppState
    @State private var editingId: String? = nil
    @State private var fName = ""
    @State private var fBase = ""
    @State private var fModel = ""
    @State private var fKey = ""
    @State private var presetSel = ""
    @State private var importText = ""
    @State private var importMsg = ""
    @State private var testMsg = ""
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("模型 · BYOK")
            Text("国内主流 + 中转站（境外模型）。Key 只存本地。")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            // 已保存
            if state.config.providers.isEmpty {
                GroupCard {
                    GRow(title: "还没有模型配置", subtitle: "下面选个预设补 Key，或粘贴中转站分享链接一键导入") { EmptyView() }
                }
            } else {
                GroupCard {
                    ForEach(Array(state.config.providers.enumerated()), id: \.element.id) { idx, p in
                        let active = (state.config.activeId == p.id)
                            || (state.config.activeId.isEmpty && idx == 0)
                        GRow(title: p.name, subtitle: (p.model.isEmpty ? "中转站默认模型" : p.model) + (p.apiKey.isEmpty ? " · ⚠ 未填 Key" : "")) {
                            HStack(spacing: 6) {
                                Button(active ? "✓ 已启用" : "启用") { state.setActive(p.id) }
                                    .buttonStyle(.borderedProminent).tint(active ? .pink : .gray).controlSize(.small)
                                Button("测试") { test(p) }.controlSize(.small).disabled(testing)
                                Button("编辑") { load(p) }.controlSize(.small)
                                Button("删除") { state.deleteProvider(p.id); if editingId == p.id { clear() } }.controlSize(.small)
                            }
                        }
                        if idx < state.config.providers.count - 1 { RowDivider() }
                    }
                }
            }

            // 中转站一键导入
            SectionHeader("从中转站导入")
            GroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("粘贴中转站分享链接 / JSON，或直接把 Codex 的 config.toml + auth.json 一起粘进来，一键导入")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        TextField("ccswitch://… 或 {\"baseUrl\":\"…\",\"apiKey\":\"…\",\"model\":\"…\"}", text: $importText)
                            .textFieldStyle(.roundedBorder)
                        Button("导入") {
                            if state.importProvider(from: importText) { importMsg = "已导入 ✓"; importText = "" }
                            else { importMsg = "没解析出配置，检查一下格式" }
                        }.buttonStyle(.borderedProminent).tint(.blue)
                    }
                    if !importMsg.isEmpty { Text(importMsg).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(14)
            }

            // 新增 / 编辑
            SectionHeader(editingId == nil ? "新增配置" : "编辑配置")
            Text("中转站只需填「API 端点 + API Key」两项，其余留空；国内模型用下面预设一键带出端点。")
                .font(.caption).foregroundStyle(.secondary)
            GroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("国内模型预设", selection: $presetSel) {
                        Text("— 中转站直接往下填；国内模型选这里 —").tag("")
                        ForEach(PRESETS, id: \.key) { Text($0.name).tag($0.key) }
                    }
                    .onChange(of: presetSel) { key in
                        if let p = PRESETS.first(where: { $0.key == key }) { fName = p.name; fBase = p.baseUrl; fModel = p.model }
                    }

                    TextField("API 端点 · Base URL（https://…/v1）", text: $fBase).textFieldStyle(.roundedBorder)
                    SecureField("API Key（仅存本地）", text: $fKey).textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 3) {
                        TextField("模型（选填）", text: $fModel).textFieldStyle(.roundedBorder)
                        Text("中转站一般留空即可；若「测试连接」报 model is required，就把中转站给的模型名填这里")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("名称（选填）", text: $fName).textFieldStyle(.roundedBorder)
                        Text("留空自动用端点域名").font(.caption2).foregroundStyle(.secondary)
                    }

                    HStack {
                        Button(editingId == nil ? "保存配置" : "保存修改") {
                            guard !fBase.isEmpty, !fKey.isEmpty else { return }
                            let name = fName.isEmpty ? deriveName(fBase) : fName
                            state.upsertProvider(id: editingId, name: name, baseUrl: fBase, model: fModel, apiKey: fKey)
                            clear()
                        }.buttonStyle(.borderedProminent).tint(.pink)
                        Button(testing ? "测试中…" : "测试连接") {
                            guard !fBase.isEmpty, !fKey.isEmpty else { testMsg = "先填端点和 Key"; return }
                            test(Provider(name: "test", baseUrl: fBase, model: fModel, apiKey: fKey))
                        }.disabled(testing)
                        Button("清空") { clear() }
                    }
                    if !testMsg.isEmpty {
                        Text(testMsg).font(.caption)
                            .foregroundStyle(testMsg.hasPrefix("✅") ? Color.green : (testMsg.hasPrefix("❌") ? Color.red : Color.secondary))
                    }
                }
                .padding(14)
            }
        }
    }

    private func load(_ p: Provider) { editingId = p.id; fName = p.name; fBase = p.baseUrl; fModel = p.model; fKey = p.apiKey }
    private func clear() { editingId = nil; fName = ""; fBase = ""; fModel = ""; fKey = ""; presetSel = "" }
    private func deriveName(_ base: String) -> String {
        if let h = URLComponents(string: base)?.host, !h.isEmpty { return h }
        return "中转站"
    }
    private func test(_ p: Provider) {
        testing = true; testMsg = "测试中…"
        Task { @MainActor in
            do {
                _ = try await LLM.chat(provider: p, system: "你是连接测试助手。", user: "回复 ok 即可。")
                testMsg = "✅ 连接成功"
            } catch {
                testMsg = "❌ " + error.localizedDescription
            }
            testing = false
        }
    }
}

// MARK: - 性格（问答生成）
struct PersonaPane: View {
    @ObservedObject var state: AppState
    @State private var text = ""
    @State private var loaded = false
    @State private var saved = false

    static let template = """
    你是阿豆，一只住在我电脑桌面上的橘猫。
    性格：慵懒、爱摸鱼、嘴硬心软，把我叫"老大"，嘴上嫌弃、行动上关心。
    说话：短、口语、像随口冒个泡；偶尔怼我两句都是为我好。
    边界：你就是一只猫，绝不假装人类、不扮演恋人或亲属。
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("性格")
            GroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("直接写它的人设 —— 它会照这个说话。可改成任意角色 / 语气 / 称呼。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    TextEditor(text: $text)
                        .font(.system(size: 13)).frame(minHeight: 132)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1)))
                        .onChange(of: text) { _ in saved = false }
                    HStack {
                        Button("恢复默认模板") { text = Self.template }.controlSize(.small)
                        Spacer()
                        if saved { Text("已保存 ✓").font(.caption).foregroundStyle(.green) }
                        Button("保存") { save() }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }.padding(14)
            }
        }
        .onAppear {
            if !loaded {
                let p = state.currentCard().persona
                text = p.isEmpty ? Self.template : p
                loaded = true
            }
        }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        state.setCard(CardData(name: "", species: "", tone: "", catchphrases: [], persona: t.isEmpty ? Self.template : t))
        saved = true
    }
}

// MARK: - 记忆 · 隐私
struct MemoryPane: View {
    @ObservedObject var state: AppState
    @State private var content = ""
    @State private var category = "偏好"
    @State private var longTerm = true
    private let cats = ["偏好", "目标", "项目", "关系", "任务", "情绪", "其它"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("记忆 · 隐私")
            GroupCard {
                GRow(title: "隐身模式", subtitle: "暂停观察与主动打扰，本次不记新记忆") {
                    Toggle("", isOn: Binding(get: { state.config.stealth }, set: { state.setStealth($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            Text("所有记忆只存在你本地（Application Support），随时可删。它懂你，但不偷看你。")
                .font(.caption).foregroundStyle(.secondary)

            SectionHeader("它记住的")
            if state.memories.isEmpty {
                GroupCard {
                    GRow(title: "还没有记忆", subtitle: "下面手动加一条；平时聊天它也会自动记住关于你的事") { EmptyView() }
                }
            } else {
                GroupCard {
                    ForEach(Array(state.memories.enumerated()), id: \.element.id) { idx, m in
                        GRow(title: m.content, subtitle: m.category + (m.longTerm ? "" : " · 仅临时")) {
                            Button("删除") { state.deleteMemory(m.id) }.controlSize(.small)
                        }
                        if idx < state.memories.count - 1 { RowDivider() }
                    }
                }
                Button("清空全部记忆") { state.clearMemories() }.controlSize(.small).tint(.red)
            }

            SectionHeader("手动添加一条")
            GroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("比如：我不喜欢被催得太急 / 我在做灵崽这个项目", text: $content)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("类别", selection: $category) { ForEach(cats, id: \.self) { Text($0) } }.frame(width: 170)
                        Toggle("长期记住", isOn: $longTerm)
                        Spacer()
                        Button("添加") {
                            state.addMemory(content: content, category: category, longTerm: longTerm)
                            content = ""
                        }.buttonStyle(.borderedProminent).tint(.indigo)
                    }
                }
                .padding(14)
            }
        }
    }
}

// MARK: - 任务 · 会思考的 todo
struct TaskPane: View {
    @ObservedObject var state: AppState
    @State private var newTask = ""
    @State private var busyId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("任务 · 陪你做")
            GroupCard {
                GRow(title: "主动督促", subtitle: "按专注 / 久坐 / 作息主动提醒（防打扰）") {
                    Toggle("", isOn: Binding(get: { state.config.proactive }, set: { state.setProactive($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "督促文案由 AI 生成", subtitle: "更有性格（费点 token）") {
                    Toggle("", isOn: Binding(get: { state.config.proactiveLLM }, set: { state.setProactiveLLM($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }

            SectionHeader("想法收集箱")
            GroupCard {
                HStack {
                    TextField("随手记一件要做的事…", text: $newTask).textFieldStyle(.roundedBorder).onSubmit(add)
                    Button("收集", action: add).buttonStyle(.borderedProminent).tint(.orange)
                }.padding(14)
            }

            SectionHeader("要做的")
            let active = state.tasks.filter { !$0.done }
            if active.isEmpty {
                GroupCard { GRow(title: "暂无任务", subtitle: "上面随手记一件，我帮你拆小、陪你做") { EmptyView() } }
            } else {
                ForEach(active) { t in card(t) }
            }

            let done = state.tasks.filter { $0.done }
            if !done.isEmpty {
                SectionHeader("已完成 · \(done.count)")
                GroupCard {
                    ForEach(Array(done.prefix(8).enumerated()), id: \.element.id) { i, t in
                        GRow(title: t.title, subtitle: "已完成 ✓") { Button("删除") { state.deleteTask(t.id) }.controlSize(.small) }
                        if i < min(done.count, 8) - 1 { RowDivider() }
                    }
                }
            }
        }
    }

    private func add() { state.addTask(newTask); newTask = "" }
    private func doBreak(_ t: TodoItem) {
        busyId = t.id
        Task { @MainActor in await state.breakdown(t.id); busyId = nil }
    }

    private func card(_ t: TodoItem) -> some View {
        GroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(t.title).font(.system(size: 14, weight: .semibold))
                if !t.next.isEmpty {
                    Text("👉 下一步：\(t.next)").font(.caption).foregroundStyle(Color.orange)
                }
                if !t.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(t.steps.enumerated()), id: \.offset) { i, s in
                            Text("\(i + 1). \(s)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button(busyId == t.id ? "拆解中…" : "拆解") { doBreak(t) }.controlSize(.small).disabled(busyId != nil)
                    Button("陪我做 25 分钟") { state.startFocus(t.title) }.controlSize(.small).tint(.indigo)
                    Button("完成") { state.completeTask(t.id) }.controlSize(.small).tint(.green)
                    Spacer()
                    Button("删除") { state.deleteTask(t.id) }.controlSize(.small)
                }
            }.padding(14)
        }
    }
}
