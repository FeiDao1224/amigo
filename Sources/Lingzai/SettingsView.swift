import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct NavItem: Identifiable {
    let key, title, subtitle, icon: String
    let color: Color
    var id: String { key }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var sel = "character"
    @State private var showCustom = false

    private let items: [NavItem] = [
        .init(key: "general",  title: "通用", subtitle: "系统与基础行为",       icon: "gearshape.fill",         color: .gray),
        .init(key: "model",    title: "模型", subtitle: "接入大模型",           icon: "cpu",                    color: .blue),
        .init(key: "character",title: "形象", subtitle: "角色 · 自定义 · 动作",  icon: "pawprint.fill",          color: .pink),
        .init(key: "persona",  title: "性格", subtitle: "名字 · 人设 · 记忆 · 隐私", icon: "heart.text.square.fill", color: .purple),
        .init(key: "interact", title: "交互", subtitle: "点击 · 拖拽 · 语音",     icon: "hand.tap.fill",          color: .teal),
        .init(key: "task",     title: "任务", subtitle: "后续开发",             icon: "checklist",              color: .orange),
        .init(key: "about",    title: "关于", subtitle: "版本 · 激活",          icon: "info.circle.fill",       color: .gray),
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
        .overlay(alignment: .top) {
            if !state.toast.isEmpty {
                Text(state.toast)
                    .font(.system(size: 12)).foregroundStyle(.white).lineLimit(3)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 6, y: 2).padding(.top, 14).frame(maxWidth: 460)
                    .onTapGesture { state.toast = "" }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: state.toast)
    }

    @ViewBuilder private var content: some View {
        switch sel {
        case "general":   general
        case "model":     ModelPane(state: state)
        case "character": character
        case "persona":   persona
        case "interact":  interactVoice
        case "task":      placeholder("任务", "提醒 · 督促 · 陪你做 —— 后续开发，敬请期待")
        default:          about
        }
    }

    private var dockBinding: Binding<Bool> { Binding(get: { state.config.dockVisible }, set: { state.setDockVisible($0) }) }
    private var proactiveBinding: Binding<Bool> { Binding(get: { state.config.proactive }, set: { state.setProactive($0) }) }
    private var readAloudBinding: Binding<Bool> { Binding(get: { state.config.readAloud }, set: { state.setReadAloud($0) }) }
    private var proactiveLLMBinding: Binding<Bool> { Binding(get: { state.config.proactiveLLM }, set: { state.setProactiveLLM($0) }) }
    private var stealthBinding: Binding<Bool> { Binding(get: { state.config.stealth }, set: { state.setStealth($0) }) }
    private var behaviorBinding: Binding<Bool> { Binding(get: { state.config.behaviorDriven }, set: { state.setBehaviorDriven($0) }) }
    private var agentBinding: Binding<Bool> { Binding(get: { state.config.agentMonitor }, set: { state.setAgentMonitor($0) }) }
    private func mapRow(_ title: String, _ trigger: String, _ current: String) -> some View {
        GRow(title: title) {
            Picker("", selection: Binding(get: { current }, set: { state.setMap(trigger, $0) })) {
                ForEach(state.allActions) { d in Text(d.title).tag(d.id) }
            }.labelsHidden().frame(width: 130)
        }
    }
    private func clickRow(_ title: String, _ sub: String, _ trigger: String, _ current: String) -> some View {
        GRow(title: title, subtitle: sub) {
            Picker("", selection: Binding(get: { current }, set: { state.setClick(trigger, $0) })) {
                ForEach(state.clickOptions, id: \.0) { Text($0.1).tag($0.0) }
            }.labelsHidden().frame(width: 150)
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

    private var character: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("形象")
            GroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选个角色（悬停有光效）；点最后的「自定义」上传图片生成你的专属形象。AI 动作按形象分别生成、换形象自动切换。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    CharacterPicker(state: state, onCustom: { withAnimation { showCustom.toggle() } })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
            if showCustom { CustomPetCard(state: state) }

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
                ForEach(state.allActions) { def in ActionRow(state: state, def: def) }
                NewActionCard(state: state)
            }
        }
    }

    private var persona: some View {
        VStack(alignment: .leading, spacing: 14) {
            PersonaPane(state: state).id(state.config.character)
            MemoryPane(state: state)
            privacy
        }
    }

    private var interactVoice: some View {
        VStack(alignment: .leading, spacing: 14) {
            interact
            voice
        }
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
                RowDivider(); clickRow("左键点击", "戳一下", "left", state.config.clickLeft)
                RowDivider(); clickRow("双击", "连点两下", "double", state.config.clickDouble)
                RowDivider(); clickRow("长按", "按住不放", "long", state.config.clickLong)
                RowDivider(); clickRow("右键点击", "右键", "right", state.config.clickRight)
                RowDivider()
                GRow(title: "拖动", subtitle: "移动宠物位置（会自动走 / 跑）") { Text("固定").font(.caption).foregroundStyle(.secondary) }
                RowDivider()
                GRow(title: "文件拖动", subtitle: "拖文件到它身上 → 用你的模型帮你看 / 给处理建议") {
                    Text("已开放").font(.caption).foregroundStyle(.green)
                }
            }
            Text("每个点击都能改成：某功能，或播放某个动作。动作没生成时会回退到静态 / 程序动画。")
                .font(.caption).foregroundStyle(.secondary)

            SectionHeader("助手监控（实验）")
            GroupCard {
                GRow(title: "监控 AI 助手状态", subtitle: "Claude Code / Codex 忙完、卡住要确认、报错时，桌宠冒泡告诉你") {
                    Toggle("", isOn: agentBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "接入 Claude Code", subtitle: "复制 hook 配置，贴进 ~/.claude/settings.json 的 hooks 里") {
                    Button("复制 Hook 配置") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AgentBridge.claudeHookJSON(), forType: .string)
                        state.showToast("已复制，贴进 ~/.claude/settings.json 的 hooks 里即可")
                    }.controlSize(.small)
                }
            }
            Text("原理：助手用 hook 把状态写到本机 agents/ 目录，桌宠盯着读——不偷看终端。Codex/其它助手同理，用它的 notify/hook 调 bin/agent-hook.sh。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("关于")
            GroupCard {
                GRow(title: "灵崽 Lingzai", subtitle: "被你真实行为驱动的桌面搭子") { Text("v0.1 原生内测").foregroundStyle(.secondary) }
            }
            ProPane(state: state)
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
