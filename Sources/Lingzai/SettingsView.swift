import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct NavItem: Identifiable {
    let key, title, subtitle, icon: String
    let color: Color
    var id: String { key }
}

// 自定义形象：选图 → 像素化预览 → 设为桌宠
private struct CustomPetCard: View {
    @ObservedObject var state: AppState
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
                        Button("设为桌宠") {
                            if let s = source { state.setCustomPet(from: s, rows: rows, levels: levels, flood: flood) }
                        }
                        .buttonStyle(.borderedProminent).disabled(preview == nil)
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
        .init(key: "pet",     title: "宠物",   subtitle: "形象与动作",       icon: "pawprint.fill",            color: .pink),
        .init(key: "card",    title: "性格",   subtitle: "问答定制它的性格",   icon: "sparkles",                 color: .purple),
        .init(key: "memory",  title: "记忆",   subtitle: "它记得什么·你说了算", icon: "brain.head.profile",       color: .indigo),
        .init(key: "task",    title: "任务",   subtitle: "提醒与督促",       icon: "checklist",                color: .orange),
        .init(key: "voice",   title: "语音",   subtitle: "让它开口",         icon: "waveform",                 color: .green),
        .init(key: "interact",title: "交互",   subtitle: "点击·拖拽·文件",   icon: "hand.tap.fill",            color: .teal),
        .init(key: "privacy", title: "隐私",   subtitle: "它懂你·但不偷看你",  icon: "lock.shield.fill",         color: .mint),
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
        case "card":     PersonaPane(state: state)
        case "memory":   MemoryPane(state: state)
        case "task":     TaskPane(state: state)
        case "voice":    voice
        case "interact": interact
        case "privacy":  privacy
        default:         about
        }
    }

    private var dockBinding: Binding<Bool> { Binding(get: { state.config.dockVisible }, set: { state.setDockVisible($0) }) }
    private var eyesBinding: Binding<Bool> { Binding(get: { state.config.eyesFollow }, set: { state.setEyesFollow($0) }) }
    private var proactiveBinding: Binding<Bool> { Binding(get: { state.config.proactive }, set: { state.setProactive($0) }) }
    private var readAloudBinding: Binding<Bool> { Binding(get: { state.config.readAloud }, set: { state.setReadAloud($0) }) }
    private var proactiveLLMBinding: Binding<Bool> { Binding(get: { state.config.proactiveLLM }, set: { state.setProactiveLLM($0) }) }
    private var stealthBinding: Binding<Bool> { Binding(get: { state.config.stealth }, set: { state.setStealth($0) }) }

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
                GRow(title: "眼睛跟随鼠标", subtitle: "光标移动时，阿豆的眼睛会看向你") {
                    Toggle("", isOn: eyesBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "形象", subtitle: "选角色（放好透明图后生效；小猫用眼睛跟随）") {
                    Picker("", selection: Binding(get: { state.config.character }, set: { state.setCharacter($0) })) {
                        Text("默认小猫").tag("cat")
                        Text("摸鱼鱼").tag("lazy_fish")
                        Text("看表鱼").tag("anxious_fish")
                        Text("震惊鱼").tag("shocked_fish")
                        if FileManager.default.fileExists(atPath: PetImages.dir.appendingPathComponent("custom.png").path) {
                            Text("我的形象").tag("custom")
                        }
                    }.labelsHidden().frame(width: 150)
                }
            }
            SectionHeader("自定义形象")
            CustomPetCard(state: state)
            SectionHeader("展示模式")
            HStack(spacing: 12) {
                modeCard("桌面悬浮", "贴在桌面右下角，可拖动", selected: true)
                modeCard("刘海屏", "藏进刘海，hover 唤出（即将支持）", selected: false)
            }
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
                GRow(title: "左键点击", subtitle: "对话 —— 戳一下，让阿豆说话") { EmptyView() }
                RowDivider()
                GRow(title: "右键点击", subtitle: "菜单 —— 摸头 / 设置 / 隐藏 / 退出") { EmptyView() }
                RowDivider()
                GRow(title: "拖动", subtitle: "移动宠物位置") { EmptyView() }
                RowDivider()
                GRow(title: "拖文件给它", subtitle: "把文件拖到它身上，用你的模型帮你看看 / 给处理建议") {
                    Text("已开放").font(.caption).foregroundStyle(.green)
                }
            }
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
    @State private var name = ""
    @State private var species = "猫"
    @State private var style = "慵懒高冷"
    @State private var callYou = "老大"
    @State private var active = "适度"
    @State private var nightReact = "阴阳怪气催我"
    @State private var generating = false
    @State private var msg = ""
    @State private var importText = ""
    @State private var shareMsg = ""

    private let speciesOpts = ["猫", "狗", "水豚", "鸭子", "仓鼠"]
    private let styleOpts = ["慵懒高冷", "温柔体贴", "毒舌吐槽", "元气热情", "憨憨呆萌"]
    private let activeOpts = ["话痨爱互动", "适度", "高冷少说"]
    private let nightOpts = ["温柔关心我", "阴阳怪气催我", "陪我一起摆烂"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("性格")
            GroupCard {
                let c = state.currentCard()
                GRow(title: "当前性格", subtitle: c.tone.isEmpty ? "默认设定" : c.tone) {
                    HStack(spacing: 8) {
                        Text("\(c.name) · \(c.species)").foregroundStyle(.secondary)
                        if state.config.customCard != nil {
                            Button("重置") { state.resetCard() }.controlSize(.small)
                        }
                    }
                }
            }

            SectionHeader("回答几个问题，让 AI 定制它")
            GroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    q("你想叫它什么？") { TextField("阿豆", text: $name).textFieldStyle(.roundedBorder).frame(width: 170) }
                    q("它是什么小动物？") { picker($species, speciesOpts) }
                    q("说话风格？") { picker($style, styleOpts) }
                    q("它怎么称呼你？") { TextField("老大", text: $callYou).textFieldStyle(.roundedBorder).frame(width: 170) }
                    q("有多主动？") { picker($active, activeOpts) }
                    q("你熬夜 / 摸鱼时，它？") { picker($nightReact, nightOpts) }

                    HStack(spacing: 10) {
                        Button(generating ? "生成中…" : "让 AI 生成性格") { generate() }
                            .buttonStyle(.borderedProminent).tint(.purple).disabled(generating)
                        if !msg.isEmpty { Text(msg).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .padding(14)
            }

            SectionHeader("分享 / 导入")
            GroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Button("复制当前性格分享码") { copyShare() }.buttonStyle(.bordered)
                    HStack {
                        TextField("粘贴性格分享码导入", text: $importText).textFieldStyle(.roundedBorder)
                        Button("导入") { importPersona() }.buttonStyle(.bordered)
                    }
                    if !shareMsg.isEmpty { Text(shareMsg).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(14)
            }
            Text("用你当前启用的模型生成（消耗一点点 token）。生成后立刻生效，不满意可重来或点「重置」。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func q<V: View>(_ label: String, @ViewBuilder _ control: () -> V) -> some View {
        HStack { Text(label).font(.system(size: 13)); Spacer(minLength: 8); control() }
    }
    private func picker(_ sel: Binding<String>, _ opts: [String]) -> some View {
        Picker("", selection: sel) { ForEach(opts, id: \.self) { Text($0) } }
            .labelsHidden().frame(width: 170)
    }

    private func generate() {
        generating = true; msg = ""
        let answers = "名字倾向：\(name.isEmpty ? "随意" : name)；物种：\(species)；说话风格：\(style)；称呼主人：\(callYou.isEmpty ? "随它" : callYou)；主动程度：\(active)；熬夜或摸鱼时它：\(nightReact)"
        Task { @MainActor in
            let r = await state.generatePersonality(answers: answers)
            generating = false
            switch r {
            case .success(let c): state.setCard(c); msg = "已生成：\(c.name) ✓"
            case .failure(let e): msg = e.localizedDescription
            }
        }
    }

    private func copyShare() {
        if let d = try? JSONEncoder().encode(state.currentCard()), let s = String(data: d, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s, forType: .string)
            shareMsg = "已复制分享码到剪贴板 ✓"
        }
    }
    private func importPersona() {
        guard let d = importText.data(using: .utf8) else { shareMsg = "格式不对"; return }
        if let c = try? JSONDecoder().decode(CardData.self, from: d) {
            state.setCard(c); shareMsg = "已导入：\(c.name) ✓"; importText = ""
        } else if let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let c = CardData.fromLLM(obj) {
            state.setCard(c); shareMsg = "已导入：\(c.name) ✓"; importText = ""
        } else { shareMsg = "解析失败，检查分享码" }
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
