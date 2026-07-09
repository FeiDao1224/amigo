import SwiftUI
import UniformTypeIdentifiers

struct PetView: View {
    @ObservedObject var rt: PetRuntime
    var onDrag: (Bool) -> Void          // ended?
    var onFile: (URL) -> Void
    var onSend: (String) -> Void
    var onTrigger: (String) -> Void = { _ in }

    @State private var chatInput = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 2) {
            cloudBubble
            cat
        }
        .padding(.bottom, 8)
        .frame(width: 260, height: 320, alignment: .bottom)
    }

    // 干净的毛玻璃气泡：说话显示文字；长按后同一处变输入框
    @ViewBuilder private var cloudBubble: some View {
        if rt.chatting || !rt.bubbleText.isEmpty {
            Group {
                if rt.chatting {
                    HStack(spacing: 6) {
                        TextField("", text: $chatInput)
                            .textFieldStyle(.plain).font(.system(size: 13))
                            .focused($inputFocused).frame(width: 132)
                            .onSubmit(send)
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 18))
                        }.buttonStyle(.plain).foregroundStyle(.blue)
                    }
                    .onAppear { inputFocused = true }
                    .onExitCommand { rt.chatting = false }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                } else {
                    Text(rt.bubbleText)
                        .font(.system(size: 13)).foregroundStyle(.primary)
                        .frame(maxWidth: 200).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14)))
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
            .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
        }
    }

    private func send() {
        let t = chatInput.trimmingCharacters(in: .whitespaces)
        chatInput = ""
        guard !t.isEmpty else { return }
        onSend(t)
    }

    // 宠物本体：优先 AI 动作帧；否则静态形象图 + 整图程序动画；再兜底一个占位
    private var cat: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            if !rt.actionFrames.isEmpty {
                let i = Int(t * rt.actionFPS) % rt.actionFrames.count
                Image(nsImage: rt.actionFrames[i]).resizable().interpolation(.none).scaledToFit()
                    .frame(width: 92, height: 140)
                    .scaleEffect(x: rt.facingLeft ? -1 : 1, y: 1)   // 往左走时翻转朝向
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                    .modifier(MoveMotion(kind: rt.moveMotion, time: t))
            } else if let img = PetImages.image(rt.characterImageName) {
                Image(nsImage: img).resizable().interpolation(.none).scaledToFit()
                    .frame(width: 92, height: 140)
                    .scaleEffect(x: rt.facingLeft ? -1 : 1, y: 1)   // 没生成走路帧时,静态图也随拖动方向翻转
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                    .modifier(PetMotion(state: rt.petState, time: t))
            } else {
                placeholderPet.modifier(PetMotion(state: rt.petState, time: t))
            }
        }
        .contentShape(Circle())
        .onTapGesture(count: 2) { onTrigger("double") }
        .onTapGesture { onTrigger("left") }
        .highPriorityGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { _ in onDrag(false) }
                .onEnded { _ in onDrag(true) }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in onTrigger("long") }
        )
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleDrop(providers) }
    }

    // 没有形象图时的极简兜底
    private var placeholderPet: some View {
        VStack(spacing: 4) {
            Image(systemName: "pawprint.circle.fill").font(.system(size: 46)).foregroundStyle(Color.orange.gradient)
            Text("选个形象").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 92, height: 140)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
            else if let u = item as? URL { url = u }
            if let url { DispatchQueue.main.async { onFile(url) } }
        }
        return true
    }
}
