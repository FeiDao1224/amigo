import SwiftUI
import UniformTypeIdentifiers

struct PetView: View {
    @ObservedObject var rt: PetRuntime
    var onSpeak: () -> Void
    var onOpenSettings: () -> Void
    var onTogglePet: () -> Void
    var onQuit: () -> Void
    var onDrag: (Bool) -> Void          // ended?
    var onCoffee: () -> Void
    var onWater: () -> Void
    var onFile: (URL) -> Void
    var onChat: () -> Void
    var onSend: (String) -> Void

    @State private var chatInput = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            bubble
            cat
            if rt.chatting { inputField }
        }
        .padding(.bottom, 8)
        .frame(width: 260, height: 320, alignment: .bottom)
    }

    // 连到头顶、带向下小尾巴的气泡
    @ViewBuilder private var bubble: some View {
        if !rt.bubbleText.isEmpty {
            VStack(spacing: 0) {
                Text(rt.bubbleText)
                    .font(.system(size: 13))
                    .foregroundStyle(.black.opacity(0.82))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: 200)
                Triangle().fill(.white)
                    .frame(width: 16, height: 9)
                    .rotationEffect(.degrees(180))
                    .offset(y: -1)
            }
            .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
            .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
        }
    }

    // 点宠物在它下方弹出的输入框
    private var inputField: some View {
        HStack(spacing: 6) {
            TextField("跟阿豆说…", text: $chatInput)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .frame(width: 150)
                .onSubmit(send)
            Button("发", action: send).controlSize(.small).buttonStyle(.borderedProminent)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        .onAppear { inputFocused = true }
        .onExitCommand { rt.chatting = false }
    }
    private func send() {
        let t = chatInput.trimmingCharacters(in: .whitespaces)
        chatInput = ""
        guard !t.isEmpty else { return }
        onSend(t)
    }

    // 宠物本体：有角色图用图、没有用代码猫；整图程序动画（TimelineView 时间驱动）
    private var cat: some View {
        TimelineView(.animation) { tl in
            if rt.animator.currentFrame != nil {
                petVisual
            } else {
                petVisual
                    .modifier(PetMotion(state: rt.petState, time: tl.date.timeIntervalSinceReferenceDate))
            }
        }
        .contentShape(Circle())
        .onTapGesture { onChat() }
        .highPriorityGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { _ in onDrag(false) }
                .onEnded { _ in onDrag(true) }
        )
        .contextMenu {
            Button("摸摸头 🐾") { onSpeak() }
            Button("喂咖啡 ☕") { onCoffee() }
            Button("喂水 💧") { onWater() }
            Divider()
            Menu("动作调试") {
                ForEach(PetAction.allCases) { action in
                    Button(action.displayName) { rt.playAction(action) }
                }
                Divider()
                Button("随机陪伴动作") { rt.playRandomCompanionAction() }
            }
            Divider()
            Button("打开设置…") { onOpenSettings() }
            Button("隐藏宠物") { onTogglePet() }
            Divider()
            Button("退出灵崽") { onQuit() }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleDrop(providers) }
    }

    @ViewBuilder private var petVisual: some View {
        if rt.animator.currentFrame != nil {
            AnimatedPetImage(animator: rt.animator)
        } else if let img = PetImages.image(rt.characterImageName) {
            Image(nsImage: img).resizable().scaledToFit()
                .frame(width: 80, height: 125)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
        } else {
            drawnCat
    }
}

private struct AnimatedPetImage: View {
    @ObservedObject var animator: PetAnimator

    var body: some View {
        if let frame = animator.currentFrame {
            Image(nsImage: frame)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .scaledToFit()
                .frame(width: displayWidth, height: displayHeight)
        }
    }

    private var displayWidth: CGFloat {
        guard let profile = animator.profile else { return 160 }
        return CGFloat(profile.pixelCanvasWidth)
    }

    private var displayHeight: CGFloat {
        guard let profile = animator.profile else { return 192 }
        return CGFloat(profile.pixelCanvasHeight)
    }
}

    private var drawnCat: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.16)).frame(width: 98, height: 16).offset(y: 76).blur(radius: 3)
            Capsule().fill(furGrad).frame(width: 18, height: 56).rotationEffect(.degrees(28)).offset(x: 46, y: 40)
            Ellipse().fill(furGrad).frame(width: 96, height: 106).offset(y: 30).shadow(color: .black.opacity(0.12), radius: 5, y: 3)
            Ellipse().fill(.white.opacity(0.55)).frame(width: 40, height: 60).offset(y: 40)
            Capsule().fill(pawColor).frame(width: 24, height: 18).offset(x: -17, y: 70)
            Capsule().fill(pawColor).frame(width: 24, height: 18).offset(x: 17, y: 70)
            head.offset(y: -36)
        }
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

    private var head: some View {
        ZStack {
            // 耳朵
            Triangle().fill(furGrad).frame(width: 30, height: 28).offset(x: -20, y: -26)
            Triangle().fill(furGrad).frame(width: 30, height: 28).offset(x: 20, y: -26)
            Triangle().fill(pinkEar).frame(width: 15, height: 14).offset(x: -20, y: -22)
            Triangle().fill(pinkEar).frame(width: 15, height: 14).offset(x: 20, y: -22)

            // 脸
            Circle().fill(furGrad).frame(width: 66, height: 62)
                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)

            eye.offset(x: -14, y: -2)
            eye.offset(x: 14, y: -2)

            // 鼻子
            Triangle().fill(Color(red: 0.92, green: 0.5, blue: 0.55))
                .rotationEffect(.degrees(180)).frame(width: 8, height: 6).offset(y: 9)
        }
    }

    private var eye: some View {
        ZStack {
            Ellipse().fill(.white).frame(width: 13, height: 16)
            Circle().fill(Color(red: 0.12, green: 0.10, blue: 0.12))
                .frame(width: 8, height: 8)
                .offset(x: rt.eyeVector.width * 3, y: rt.eyeVector.height * 3)
            Circle().fill(.white.opacity(0.9)).frame(width: 2.6, height: 2.6)
                .offset(x: rt.eyeVector.width * 3 - 1, y: rt.eyeVector.height * 3 - 2)
        }
        .animation(.easeOut(duration: 0.1), value: rt.eyeVector)
    }

    private var furGrad: LinearGradient {
        LinearGradient(colors: [Color(red: 0.99, green: 0.75, blue: 0.44),
                                Color(red: 0.93, green: 0.62, blue: 0.31)],
                       startPoint: .top, endPoint: .bottom)
    }
    private var pawColor: Color { Color(red: 0.90, green: 0.60, blue: 0.30) }
    private var pinkEar: Color { Color(red: 0.98, green: 0.78, blue: 0.78) }
}
