import SwiftUI
import AppKit
import UniformTypeIdentifiers

// 动作卡片：预览 + 生成/重生成 + 点选默认 + 自定义可删
struct ActionRow: View {
    @ObservedObject var state: AppState
    let def: AppState.ActionDef
    private var status: String { state.actionStatus[def.id] ?? "" }
    private var character: String { state.config.character }
    private var made: Bool { SpriteGen.exists(character: character, action: def.id) }
    private var isCurrent: Bool { state.config.activeAction == def.id }

    var body: some View {
        VStack(spacing: 6) {
            ActionPreview(character: character, id: def.id, fps: def.fps).id("\(character)-\(status)")
                .frame(maxWidth: .infinity).frame(height: 72)
            Text(def.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            statusText
            HStack(spacing: 6) {
                if !def.builtin {
                    Button { state.deleteCustomAction(def.id) } label: { Image(systemName: "trash") }.controlSize(.mini)
                }
                Button(status == "generating" ? "生成中" : (made ? "重生成" : "生成")) {
                    Task { await state.generateActionDef(def) }
                }.controlSize(.mini).buttonStyle(.borderedProminent).disabled(status == "generating")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { state.setActiveAction(def.id) }
    }
    @ViewBuilder private var statusText: some View {
        if status == "generating" { Text("生成中…").font(.caption2).foregroundStyle(.secondary) }
        else if status == "failed" { Text("生成失败").font(.caption2).foregroundStyle(.red) }
        else if made { Text(isCurrent ? "当前播放" : "已生成").font(.caption2).foregroundStyle(.green) }
        else { Text("未生成").font(.caption2).foregroundStyle(.secondary) }
    }
}

// 动作预览：循环播放该形象该动作的帧
struct ActionPreview: View {
    let character: String
    let id: String
    let fps: Double
    @State private var frames: [NSImage] = []
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05))
            if frames.isEmpty {
                Image(systemName: "sparkles").foregroundStyle(.secondary)
            } else {
                TimelineView(.animation) { tl in
                    let i = Int(tl.date.timeIntervalSinceReferenceDate * fps) % frames.count
                    Image(nsImage: frames[i]).resizable().interpolation(.none).scaledToFit().padding(4)
                }
            }
        }
        .onAppear { frames = SpriteGen.loadFrames(character: character, action: id) }
    }
}

// 新建动作：描述一个动作 → 生成
struct NewActionCard: View {
    @ObservedObject var state: AppState
    @State private var show = false
    @State private var title = ""
    @State private var desc = ""
    var body: some View {
        Button { show = true } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.secondary)
                Text("新建动作").font(.system(size: 12, weight: .medium))
                Text("描述一个动作").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).frame(height: 130)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(.secondary.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("新建动作").font(.headline)
                TextField("名称，如 挥手", text: $title).textFieldStyle(.roundedBorder)
                TextField("描述动作，如 开心地挥手打招呼", text: $desc, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4)
                Text("会以当前形象为参考生成；创建后点它的「生成」。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("取消") { show = false }
                    Button("创建") {
                        state.addCustomAction(title: title, desc: desc); title = ""; desc = ""; show = false
                    }.buttonStyle(.borderedProminent).disabled(desc.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.padding(16).frame(width: 300)
        }
    }
}

// 形象卡片：悬停时光斑跟随鼠标 + 彩色发光描边 + 抬升
struct CharacterCard: View {
    let id: String
    let name: String
    let selected: Bool
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil          // 仅自定义形象可删
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
        .overlay(alignment: .topTrailing) {
            if let onDelete, hover != nil {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain).padding(4)
                .help("删除这个形象")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onContinuousHover { phase in
            switch phase { case .active(let p): hover = p; case .ended: hover = nil }
        }
        .onTapGesture { onTap() }
    }
}

struct CharacterPicker: View {
    @ObservedObject var state: AppState
    var onCustom: () -> Void = {}
    // 显示名：性格设置里给了名字就用名字，否则用形象默认名
    private func displayName(_ id: String, _ fallback: String) -> String {
        if let n = state.config.personas[id]?.name, !n.trimmingCharacters(in: .whitespaces).isEmpty { return n }
        return fallback
    }
    // 内置(香蕉猫=默认 + 看表鱼) + 用户自定义；正在使用的形象排到最前
    private var chars: [(String, String, Bool)] {   // (id, 名称, 可删?)
        var a: [(String, String, Bool)] = [
            ("banana_cat", displayName("banana_cat", "香蕉猫"), false),
            ("anxious_fish", displayName("anxious_fish", "看表鱼"), false),
        ]
        a += state.config.customPets.map { ($0.id, displayName($0.id, $0.name), true) }
        if let idx = a.firstIndex(where: { $0.0 == state.config.character }), idx > 0 {
            let cur = a.remove(at: idx); a.insert(cur, at: 0)   // 当前形象置顶
        }
        return a
    }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chars, id: \.0) { it in
                    CharacterCard(id: it.0, name: it.1, selected: state.config.character == it.0,
                                  onTap: { state.setCharacter(it.0) },
                                  onDelete: it.2 ? { state.deleteCustomPet(it.0) } : nil)
                }
                CustomAddCard { onCustom() }          // 末尾：点它上传图片，生成的新形象会追加在后面
            }.padding(.horizontal, 2).padding(.vertical, 6)
        }
    }
}

// 形象网格末尾的「自定义」卡片
private struct CustomAddCard: View {
    let onTap: () -> Void
    @State private var hover = false
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(.secondary)
                .frame(width: 74, height: 82)
            Text("自定义").font(.system(size: 11))
        }
        .frame(width: 92, height: 116)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: hover ? 2 : 1, dash: [5]))
            .foregroundStyle(hover ? Color.accentColor : Color.secondary.opacity(0.5)))
        .scaleEffect(hover ? 1.05 : 1)
        .animation(.easeOut(duration: 0.18), value: hover)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hover = $0 }
        .onTapGesture { onTap() }
    }
}

// 激活页（服务器激活 + 试用状态）
struct ProPane: View {
    @ObservedObject var state: AppState
    @State private var code = ""
    @State private var busy = false
    @State private var msg = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(License.enforced ? "激活" : "版本")
            GroupCard {
                if !License.enforced {
                    GRow(title: "免费版", subtitle: "当前全部功能免费使用，无需激活码。") { EmptyView() }
                } else if state.licensed && !state.licenseExpired {
                    GRow(title: "已激活 ✓", subtitle: expiryText) {
                        Button("注销") { state.deactivate(); code = ""; msg = "" }.controlSize(.small)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(trialText).font(.system(size: 12)).foregroundStyle(state.entitled ? Color.secondary : Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            TextField("输入激活码 LZ-…", text: $code).textFieldStyle(.roundedBorder)
                            Button(busy ? "激活中…" : "激活") { activate() }
                                .buttonStyle(.borderedProminent).disabled(busy || code.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if !msg.isEmpty { Text(msg).font(.caption).foregroundStyle(msg == "已激活" ? .green : .red) }
                        Text("激活码在购买后获得，一码绑定本机；服务器可吊销/到期。").font(.caption2).foregroundStyle(.secondary)
                    }.padding(14)
                }
            }
        }
    }

    private var expiryText: String {
        if let e = state.config.licenseExpiresAt { return "有效期至 " + fmt(e) }
        return "永久授权，感谢支持"
    }
    private var trialText: String {
        state.entitled
            ? "免费试用中，还剩 \(state.trialDaysLeft) 天。输入激活码可解锁并绑定本机。"
            : "试用已到期，输入激活码后继续使用。"
    }
    private func fmt(_ ms: Double) -> String {
        let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd"
        return d.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
    private func activate() {
        busy = true; msg = ""
        Task { @MainActor in
            let err = await state.activate(code: code)
            busy = false; msg = err.isEmpty ? "已激活" : err
        }
    }
}

// 自定义形象：≤3 张参考图 → 有模型走 AI 精修(拟人化加四肢) / 无模型走本地像素化
struct CustomPetCard: View {
    @ObservedObject var state: AppState
    var onUpgrade: () -> Void = {}
    @State private var images: [NSImage] = []
    @State private var preview: NSImage?
    @State private var level: Double = 0.3    // 偏细腻：更能保留参考图的神态/花纹
    @State private var cutout = true
    @State private var anthro = true
    @State private var desc = ""
    @State private var localWorking = false

    private var rows: Int { Int((110 - level * 46).rounded()) }
    private var levels: Int { level > 0.6 ? 4 : 5 }
    private var hasModel: Bool { state.hasModel }

    var body: some View {
        GroupCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(hasModel
                     ? "已配置模型 → AI 精修。会尽量还原参考图的神态 / 花纹 / 表情，做到「像但不照搬」；多角度加 2–3 张更传神。像素程度调「细腻」更还原。"
                     : "未配置模型 → 本地像素化。去「模型」页配置后，这里会自动改用 AI 生成，效果更好。")
                    .font(.system(size: 11)).foregroundStyle(hasModel ? .green : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label("请使用原创或你有权使用的素材；不要生成受版权 / 商标保护的卡通形象或他人肖像。", systemImage: "checkmark.shield")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 生成选项：直接放在这里，不用先加图也能设
                if hasModel {
                    Toggle("拟人化（没手脚的自动加脸 + 四肢，好做动作）", isOn: $anthro)
                        .toggleStyle(.checkbox).font(.system(size: 11))
                }
                HStack(spacing: 8) {
                    Text("像素程度").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("细腻").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $level, in: 0...1) { editing in if !editing && !hasModel { rebuild() } }
                    Text("块状").font(.caption2).foregroundStyle(.secondary)
                    if !hasModel {
                        Toggle("抠背景", isOn: $cutout).toggleStyle(.checkbox).font(.system(size: 11))
                            .onChange(of: cutout) { _ in rebuild() }
                    }
                }

                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { idx, img in
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: img).resizable().scaledToFill()
                                .frame(width: 62, height: 78).clipShape(RoundedRectangle(cornerRadius: 8))
                            Button { images.remove(at: idx); rebuild() } label: {
                                Image(systemName: "xmark.circle.fill")
                            }.buttonStyle(.plain).foregroundStyle(.white, .black.opacity(0.55)).padding(2)
                        }
                    }
                    if images.count < 3 {
                        Button { pick() } label: {
                            VStack(spacing: 3) { Image(systemName: "plus").font(.title3); Text("加图").font(.caption2) }
                                .frame(width: 62, height: 78).foregroundStyle(.secondary)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary.opacity(0.6)))
                        }.buttonStyle(.plain)
                    }
                    if !hasModel, let p = preview {
                        Image(nsImage: p).resizable().interpolation(.none).scaledToFit()
                            .frame(width: 62, height: 78)
                            .overlay(alignment: .bottom) { Text("预览").font(.caption2).foregroundStyle(.secondary) }
                    }
                    if localWorking || state.customBusy { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }
                .onDrop(of: [.image, .fileURL], isTargeted: nil) { loadDropped($0) }

                if !images.isEmpty {
                    if hasModel {
                        TextField("补充描述（可选）：保留它的表情 / 花纹更明显 / 戴顶帽子…", text: $desc)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        HStack {
                            if !state.customMsg.isEmpty {
                                Text(state.customMsg).font(.caption)
                                    .foregroundStyle(state.customMsg.hasPrefix("失败") ? .red : (state.customMsg.hasPrefix("已生成") ? .green : .secondary))
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button(state.customBusy ? "生成中…" : "AI 生成并设为桌宠") {
                                Task { await state.setCustomPetAI(images: images, anthropomorphize: anthro, pixelLevel: level, description: desc) }
                            }.buttonStyle(.borderedProminent).disabled(state.customBusy)
                        }
                    } else {
                        HStack {
                            Text("本机像素化，图片不上传（配模型后可 AI 精修 + 拟人化 + 描述）。").font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer()
                            Button("设为桌宠") {
                                if let s = images.first { state.setCustomPet(from: s, rows: rows, levels: levels, cutout: cutout) }
                            }.buttonStyle(.borderedProminent).disabled(preview == nil)
                        }
                    }
                }
            }.padding(14)
        }
    }

    private func addImage(_ img: NSImage) { if images.count < 3 { images.append(img); state.customMsg = ""; rebuild() } }

    private func rebuild() {
        guard !hasModel, let s = images.first else { preview = images.isEmpty ? nil : preview; return }
        localWorking = true
        let (r, l, c) = (rows, levels, cutout)
        DispatchQueue.global(qos: .userInitiated).async {
            let out = Pixelizer.pixelize(s, rows: r, levels: l, scale: 3, cutout: c)
            DispatchQueue.main.async { preview = out; localWorking = false }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) { addImage(img) }
    }

    private func loadDropped(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        if p.canLoadObject(ofClass: NSImage.self) {
            _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage { DispatchQueue.main.async { addImage(img) } }
            }
            return true
        }
        p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
            else if let u = item as? URL { url = u }
            if let url, let img = NSImage(contentsOf: url) { DispatchQueue.main.async { addImage(img) } }
        }
        return true
    }
}
