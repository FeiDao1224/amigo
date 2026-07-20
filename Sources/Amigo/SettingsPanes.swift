import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 模型页
struct ModelPane: View {
    @ObservedObject var state: AppState
    @State private var editingId: String? = nil
    @State private var fName = ""
    @State private var fBase = ""
    @State private var fModel = ""
    @State private var fKey = ""
    @State private var testMsg = ""
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("模型")
            Text("配置一个大模型服务：API 端点 + Key + 模型。Key 只存在本机配置里。")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            // 已保存
            if state.config.providers.isEmpty {
                GroupCard {
                    GRow(title: "还没有模型配置", subtitle: "在下面手动填 API 端点 + Key（+ 模型）") { EmptyView() }
                }
            } else {
                GroupCard {
                    ForEach(Array(state.config.providers.enumerated()), id: \.element.id) { idx, p in
                        let active = (state.config.activeId == p.id)
                            || (state.config.activeId.isEmpty && idx == 0)
                        GRow(title: p.name, subtitle: (p.model.isEmpty ? "中转站默认模型" : p.model) + (state.hasCredential(for: p.id) ? " · Key 已保存" : " · ⚠ 未填 Key")) {
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

            // 新增 / 编辑
            SectionHeader(editingId == nil ? "新增配置" : "编辑配置")
            Text("填 API 端点 + Key + 模型（OpenAI 兼容端点 / 中转站均可）。Key 只存在本机配置里。")
                .font(.caption).foregroundStyle(.secondary)
            GroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("API 端点 · Base URL（https://…/v1）", text: $fBase).textFieldStyle(.roundedBorder)
                    SecureField(editingId == nil ? "API Key（只存在本机 config.json）" : "API Key（留空则保留已保存的 Key）", text: $fKey)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 3) {
                        TextField("模型（选填）", text: $fModel).textFieldStyle(.roundedBorder)
                        Text("有的服务必须填模型名；不确定就填服务商给的默认模型")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("名称（选填）", text: $fName).textFieldStyle(.roundedBorder)
                        Text("留空自动用端点域名").font(.caption2).foregroundStyle(.secondary)
                    }

                    HStack {
                        Button(editingId == nil ? "保存配置" : "保存修改") {
                            guard !fBase.isEmpty else { return }
                            if editingId == nil && fKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
                            let name = fName.isEmpty ? deriveName(fBase) : fName
                            let key = fKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            if state.upsertProvider(id: editingId, name: name, baseUrl: fBase, model: fModel, apiKey: key.isEmpty ? nil : key) {
                                clear()
                            }
                        }.buttonStyle(.borderedProminent).tint(.pink)
                        Button(testing ? "测试中…" : "测试连接") {
                            let savedKey = editingId.flatMap { state.credential(for: $0) } ?? ""
                            let key = fKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? savedKey : fKey
                            guard !fBase.isEmpty, !key.isEmpty else { testMsg = "先填端点和 Key"; return }
                            test(Provider(id: editingId ?? UUID().uuidString, name: "test", baseUrl: fBase, model: fModel, apiKey: key))
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

    private func load(_ p: Provider) { editingId = p.id; fName = p.name; fBase = p.baseUrl; fModel = p.model; fKey = "" }
    private func clear() { editingId = nil; fName = ""; fBase = ""; fModel = ""; fKey = "" }
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
    @State private var text = ""
    @State private var loaded = false
    @State private var editing = false

    /// 空人设时给用户的示例模板（照着改就行，不预设物种）
    static let template = """
    你是住在我电脑桌面上的小家伙。
    性格：慵懒、爱摸鱼、嘴硬心软，把我叫"老大"，嘴上嫌弃、行动上关心。
    说话：短、口语、像随口冒个泡；偶尔怼我两句都是为我好。
    边界：绝不假装人类、不扮演恋人或亲属。
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("名字 · 性格")
            if editing { editor } else { card }
        }
        .onAppear {
            if !loaded {
                let c = state.currentCard()
                name = c.name
                text = c.persona.isEmpty ? Self.template : c.persona
                loaded = true
            }
        }
    }

    // 收起：一张卡片显示名字 + 人设摘要
    private var card: some View {
        GroupCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(name.isEmpty ? "（未命名）" : name).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button("编辑") { editing = true }.controlSize(.small)
                }
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(6).fixedSize(horizontal: false, vertical: true)
                Text("名字和人设跟「当前形象」绑定，换形象各自切换、不会串。")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(14)
        }
    }

    // 展开：编辑名字 + 人设
    private var editor: some View {
        GroupCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("名字").font(.system(size: 12))
                    TextField("给它起个名", text: $name).textFieldStyle(.roundedBorder)
                }
                Text("人设（它会照这个说话）").font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.system(size: 13)).frame(minHeight: 130)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1)))
                HStack {
                    Button("恢复默认模板") { text = Self.template }.controlSize(.small)
                    Spacer()
                    Button("取消") {
                        let c = state.currentCard(); name = c.name
                        text = c.persona.isEmpty ? Self.template : c.persona; editing = false
                    }.controlSize(.small)
                    Button("保存") { save(); editing = false }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            }.padding(14)
        }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = name.trimmingCharacters(in: .whitespaces)
        state.setCard(CardData(name: n, persona: t.isEmpty ? Self.template : t))
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
                RowDivider()
                GRow(title: "自动记住对话", subtitle: "开启后，才会把最近对话发送给模型提炼长期记忆；默认关闭") {
                    Toggle("", isOn: Binding(get: { state.config.autoMemory }, set: { state.setAutoMemory($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            Text("所有记忆只存在你本地（Application Support），随时可删。开启自动记忆时，提炼所需的最近对话会发送给你选择的模型。")
                .font(.caption).foregroundStyle(.secondary)

            SectionHeader("它记住的")
            if state.memories.isEmpty {
                GroupCard {
                    GRow(title: "还没有记忆", subtitle: state.config.autoMemory ? "平时聊天会按你的设置自动提炼，也可在下面手动添加" : "在下面手动加一条；自动记忆目前已关闭") { EmptyView() }
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
                    TextField("比如：我不喜欢被催得太急 / 我在做Amigo这个项目", text: $content)
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
