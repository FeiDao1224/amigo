import SwiftUI
import AppKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case companion, character, interact, model, general, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .companion: return "陪伴"
        case .character: return "形象"
        case .interact:  return "交互"
        case .model:     return "模型"
        case .general:   return "通用"
        case .about:     return "关于"
        }
    }
    var icon: String {
        switch self {
        case .companion: return "heart.fill"
        case .character: return "pawprint.fill"
        case .interact:  return "hand.tap.fill"
        case .model:     return "cpu"
        case .general:   return "gearshape.fill"
        case .about:     return "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var showCustom = false

    private var page: Binding<SettingsPage> {
        Binding(
            get: { SettingsPage(rawValue: state.settingsPage) ?? .companion },
            set: { state.settingsPage = $0.rawValue }
        )
    }

    var body: some View {
        ZStack {
            VisualEffectView().ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                    .padding(.top, 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .overlay(alignment: .top) { toast }
        .animation(.easeOut(duration: 0.2), value: state.toast)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPage.allCases) { item in
                Button {
                    page.wrappedValue = item
                } label: {
                    SidebarRow(title: item.title, icon: item.icon, selected: page.wrappedValue == item)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
            Spacer()
        }
        .padding(.top, 36)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 176)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var toast: some View {
        if !state.toast.isEmpty {
            Button { state.toast = "" } label: {
                Text(state.toast)
                    .font(.system(size: 12)).foregroundStyle(.white).lineLimit(3)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 14).frame(maxWidth: 460)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("错误：\(state.toast)")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder private var content: some View {
        switch page.wrappedValue {
        case .companion: companion
        case .character: character
        case .interact:  interact
        case .model:     ModelPane(state: state)
        case .general:   general
        case .about:     about
        }
    }

    private var dockBinding: Binding<Bool> { Binding(get: { state.config.dockVisible }, set: { state.setDockVisible($0) }) }
    private var proactiveBinding: Binding<Bool> { Binding(get: { state.config.proactive }, set: { state.setProactive($0) }) }
    private var proactiveLLMBinding: Binding<Bool> { Binding(get: { state.config.proactiveLLM }, set: { state.setProactiveLLM($0) }) }
    private var stealthBinding: Binding<Bool> { Binding(get: { state.config.stealth }, set: { state.setStealth($0) }) }
    private var behaviorBinding: Binding<Bool> { Binding(get: { state.config.behaviorDriven }, set: { state.setBehaviorDriven($0) }) }
    private var senseAppBinding: Binding<Bool> { Binding(get: { state.config.senseFrontApp }, set: { state.setSenseFrontApp($0) }) }
    private var followWindowBinding: Binding<Bool> { Binding(get: { state.config.followWindow }, set: { state.setFollowWindow($0) }) }

    private func clickRow(_ title: String, _ sub: String, _ trigger: String, _ current: String) -> some View {
        GRow(title: title, subtitle: sub) {
            Picker("", selection: Binding(get: { current }, set: { state.setClick(trigger, $0) })) {
                ForEach(state.clickOptions, id: \.0) { Text($0.1).tag($0.0) }
            }.labelsHidden().frame(width: 150)
        }
    }

    private func confirm(_ title: String, _ msg: String) -> Bool {
        let a = NSAlert()
        a.messageText = title; a.informativeText = msg; a.alertStyle = .warning
        a.addButton(withTitle: "确认"); a.addButton(withTitle: "取消")
        return a.runModal() == .alertFirstButtonReturn
    }

    // MARK: 陪伴
    private var companion: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("陪伴", page: true)
            CompanionPane(state: state)
            PersonaPane(state: state).id(state.config.character)
            MemoryPane(state: state)
        }
    }

    // MARK: 通用
    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("通用", page: true)
            GroupCard {
                GRow(title: "在 Dock 显示图标", subtitle: "关掉就只留在菜单栏") {
                    Toggle("", isOn: dockBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "开机自启", subtitle: "登录后自动打开") {
                    Toggle("", isOn: Binding(get: { LaunchAtLogin.isEnabled }, set: { LaunchAtLogin.set($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "隐身", subtitle: "先别看我：不观察、不撒娇、不催促") {
                    Toggle("", isOn: stealthBinding).labelsHidden().toggleStyle(.switch)
                }
            }

            SectionHeader("督促（可选）")
            GroupCard {
                GRow(title: "久坐和熬夜才说话", subtitle: "默认陪伴不靠这个") {
                    Toggle("", isOn: proactiveBinding).labelsHidden().toggleStyle(.switch)
                }
                if state.config.proactive {
                    RowDivider()
                    GRow(title: "督促文案用模型写", subtitle: "更有性格，会多花一点 token") {
                        Toggle("", isOn: proactiveLLMBinding).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
            if state.config.proactive {
                Text("专注 45 分钟、久坐 90 分钟、23 点以后。只在你在电脑前时说，至少隔 18 分钟。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SectionHeader("本机数据")
            GroupCard {
                GRow(title: "打开数据文件夹", subtitle: "聊天、记忆、人设、Key 都在这里") {
                    Button("在访达中打开") { state.revealDataFolder() }
                }
                RowDivider()
                GRow(title: "导出", subtitle: "复制聊天和记忆，不含 Key") {
                    Button("导出…") { state.exportData() }
                }
                RowDivider()
                GRow(title: "让它忘记我", subtitle: "只清记忆，模型和性格留下") {
                    Button("清空记忆") {
                        if confirm("清空全部记忆？", "它将忘记关于你的一切，无法恢复。") { state.forgetMe() }
                    }
                }
                RowDivider()
                GRow(title: "清空本地内容", subtitle: "聊天、记忆、形象、人设、动作和位置；Key 留在「模型」") {
                    Button("清空…") {
                        if confirm("清空本地内容数据？", "聊天记录、记忆、自定义形象、人设、动作和位置都会被删除，无法恢复。") { state.wipeAllData() }
                    }.tint(.red)
                }
            }
        }
    }

    // MARK: 形象
    private var character: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("形象", page: true)
            GroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("点选角色。最后一个「自定义」可上传图片。动作按形象分开存。")
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
                    Text("用当前形象生成 9 帧像素动作。一键只做内置 6 个；自建的在卡片上单独生成。点卡片设为默认播放。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !state.hasModel {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).font(.system(size: 13))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("生成动作需要先接入模型")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("内置形象自带动作仍能用。生成、重做或自定义形象，先去「模型」。")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("去配置模型") { state.settingsPage = SettingsPage.model.rawValue }
                                    .buttonStyle(.borderedProminent).controlSize(.small).padding(.top, 2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.orange.opacity(0.10)))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.orange.opacity(0.28)))
                    }
                    HStack(spacing: 10) {
                        Button(state.batchGenerating ? "生成中…" : "一键生成默认 6 个动作") {
                            state.startGenerateAllActions()
                        }.buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(state.batchGenerating || !state.hasModel)
                        if state.batchGenerating {
                            Text(state.batchProgress).font(.caption).foregroundStyle(.secondary)
                            Button("取消") { state.cancelGenerateAllActions() }.controlSize(.small)
                        }
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

    // MARK: 交互
    private var interact: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("交互", page: true)
            GroupCard {
                clickRow("左键", "戳一下", "left", state.config.clickLeft)
                RowDivider(); clickRow("双击", "连点两下", "double", state.config.clickDouble)
                RowDivider(); clickRow("长按", "按住不放", "long", state.config.clickLong)
                RowDivider()
                GRow(title: "右键", subtitle: "打开下面勾选的菜单") {
                    Text("菜单").font(.caption).foregroundStyle(.secondary)
                }
            }

            SectionHeader("动作怎么切")
            GroupCard {
                GRow(title: "跟着你的操作切动作", subtitle: "要先生成对应动作") {
                    Toggle("", isOn: behaviorBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "拖动", subtitle: "拖得越快，播得越快") {
                    Picker("", selection: Binding(get: { state.config.mapDrag }, set: { state.setMap("drag", $0) })) {
                        ForEach(state.allActions) { d in Text(d.title).tag(d.id) }
                    }.labelsHidden().frame(width: 130)
                }
                RowDivider()
                GRow(title: "对话中") {
                    Picker("", selection: Binding(get: { state.config.mapChat }, set: { state.setMap("chat", $0) })) {
                        ForEach(state.allActions) { d in Text(d.title).tag(d.id) }
                    }.labelsHidden().frame(width: 130)
                }
                RowDivider()
                GRow(title: "空闲", subtitle: "没操作时；挂机久了会睡") {
                    Picker("", selection: Binding(get: { state.config.activeAction }, set: { state.setActiveAction($0) })) {
                        ForEach(state.allActions) { d in Text(d.title).tag(d.id) }
                    }.labelsHidden().frame(width: 130)
                }
            }

            SectionHeader("在场")
            GroupCard {
                GRow(title: "贴住当前窗口", subtitle: "蹲在正在用的窗口右下角；手拖开一次，切窗口再跟") {
                    Toggle("", isOn: followWindowBinding).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                GRow(title: "回复里带上正在用的软件", subtitle: "只发应用名。关掉或隐身就不看") {
                    Toggle("", isOn: senseAppBinding).labelsHidden().toggleStyle(.switch)
                }
            }

            SectionHeader("右键菜单")
            GroupCard {
                rightMenuRow("speak", "摸摸头（说一句）")
                RowDivider(); rightMenuRow("feed", "喂一口")
                RowDivider(); rightMenuRow("diary", "今天来过没有")
                RowDivider(); rightMenuRow("chat", "打开对话")
                RowDivider(); rightMenuRow("settings", "打开设置")
                RowDivider(); rightMenuRow("hide", "显示 / 隐藏宠物")
                RowDivider(); rightMenuRow("quit", "退出")
                ForEach(state.allActions) { d in
                    RowDivider(); rightMenuRow("act:" + d.id, "玩：\(d.title)")
                }
            }
            Text("勾上的才会出现在右键菜单里。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func rightMenuRow(_ id: String, _ label: String) -> some View {
        GRow(title: label) {
            Toggle("", isOn: Binding(get: { state.config.rightMenuItems.contains(id) },
                                     set: { state.setRightMenuItem(id, $0) }))
                .labelsHidden().toggleStyle(.switch)
        }
    }

    // MARK: 关于
    private var about: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("关于", page: true)
            GroupCard {
                GRow(title: "Amigo", subtitle: "桌面上的情绪陪伴") {
                    Text("v\(AppInfo.version)").foregroundStyle(.secondary)
                }
                RowDivider()
                GRow(title: "开源", subtitle: "MIT · 无账号 · 无内购 · 数据只存本机") {
                    if let url = URL(string: AppInfo.repository) {
                        Link("在 GitHub 打开", destination: url).controlSize(.small)
                    }
                }
            }
            SectionHeader("它看什么")
            GroupCard {
                GRow(title: "闲置时长", subtitle: "系统提供的键鼠空闲。用来睡觉、心情和可选催促。不读窗口、不截屏、不记你打的字。") { EmptyView() }
                RowDivider()
                GRow(title: "前台应用名", subtitle: "仅当「回复里带上正在用的软件」打开时，发给你自己的模型。") { EmptyView() }
                RowDivider()
                GRow(title: "窗口边框", subtitle: "跟随时只读位置和大小，好蹲到右下角。") { EmptyView() }
            }
            Text("对话和记忆只发给你配置的模型。你可以随时导出或删除。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
