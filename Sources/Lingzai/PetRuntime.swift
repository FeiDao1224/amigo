import SwiftUI
import AppKit

enum PetState { case idle, talk, happy, shocked, bored, sleep, dragged, hop, wiggle, stretch, lean }

/// 高频动画状态：只被宠物窗观察，不连累设置窗
@MainActor
final class PetRuntime: ObservableObject {
    @Published var eyeVector: CGSize = .zero
    @Published var bubbleText: String = ""
    @Published var petState: PetState = .idle
    @Published var chatting = false                     // 下方输入框展开中
    @Published var characterImageName: String = "cat"   // cat=代码猫，或 lazy_fish / anxious_fish / shocked_fish
    @Published var actionFrames: [NSImage] = []         // 当前动作的 AI 帧：非空则优先循环播放
    @Published var actionFPS: Double = 3
    let animator = PetAnimator()

    private var currentActionKey = ""
    private var framesCache: [String: [NSImage]] = [:]

    /// 切到某动作（带缓存，可高频调用）。该动作没生成帧则清空 → 回退静态/程序动画。
    func showAction(_ key: String) {
        guard key != currentActionKey else { return }
        currentActionKey = key
        let frames = framesCache[key] ?? {
            let f = SpriteGen.loadFrames(key); framesCache[key] = f; return f
        }()
        actionFrames = frames
        actionFPS = PetAnimAction(rawValue: key)?.fps ?? 3
    }
    /// 生成/切换后刷新缓存，下一帧重新加载
    func invalidateActions() { framesCache.removeAll(); currentActionKey = "" }

    private var stateWork: DispatchWorkItem?
    func setState(_ s: PetState, revertAfter: TimeInterval? = nil) {
        petState = s
        animator.playState(s)
        stateWork?.cancel()
        guard let r = revertAfter else { return }
        let w = DispatchWorkItem { [weak self] in
            self?.petState = .idle
            self?.animator.play(.idleStand, force: true)
        }
        stateWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + r, execute: w)
    }

    func setCharacter(_ id: String) {
        characterImageName = id
        animator.loadPet(id)
    }

    func playAction(_ action: PetAction, force: Bool = true) {
        animator.play(action, force: force)
    }

    func playRandomCompanionAction() {
        animator.playRandomCompanionAction()
    }

    var activeProvider: (() -> Provider?)?
    var activeCard: (() -> CardData)?
    var speaker: Speaker?
    var shouldReadAloud: () -> Bool = { false }
    var nudgeUseLLM: () -> Bool = { false }
    var memoryContext: () -> String = { "" }

    private var clearWork: DispatchWorkItem?
    private let canned = [
        "……喵。", "急啥，先眯一会儿。", "唔……又戳我。",
        "（先在设置里配个模型，我就能真聊了）",
    ]

    func showBubble(_ text: String, sticky: Bool = false) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { bubbleText = text }
        clearWork?.cancel()
        if sticky { return }
        if text != "…" { setState(.talk, revertAfter: 2.6) }
        if shouldReadAloud() { speaker?.speak(text) }
        let w = DispatchWorkItem { [weak self] in withAnimation { self?.bubbleText = "" } }
        clearWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: w)
    }

    private var card: CardData { activeCard?() ?? .default }
    private var fullSystem: String {
        let mem = memoryContext()
        return mem.isEmpty ? card.systemPrompt : card.systemPrompt + "\n\n" + mem
    }

    func speak() {
        guard let p = activeProvider?(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else {
            showBubble(canned.randomElement()!)
            return
        }
        showBubble("…", sticky: true)
        let system = fullSystem
        Task { @MainActor in
            do {
                let reply = try await LLM.chat(provider: p, system: system,
                                               user: "（主人戳了戳你，随口说一句话吧）")
                showBubble(reply)
            } catch {
                showBubble("（脑子卡壳了…）")
                NSLog("Lingzai LLM error: \(error.localizedDescription)")
            }
        }
    }

    /// 主动督促：开关开 + 有模型时用 AI 生成有性格的一句，否则用内置文案
    func nudge(situation: String, fallback: String) {
        guard nudgeUseLLM(), let p = activeProvider?(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else {
            showBubble(fallback); return
        }
        let system = fullSystem
        Task { @MainActor in
            do {
                let line = try await LLM.chat(provider: p, system: system,
                    user: "现在的情况：\(situation)。用你的性格，主动对主人说一句简短的提醒或关心，不超过 25 字，别解释。")
                showBubble(line)
            } catch { showBubble(fallback) }
        }
    }

    /// 拖文件给它 → 简短反应 / 处理建议
    func handleFile(_ url: URL) {
        let name = url.lastPathComponent
        guard let p = activeProvider?(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else {
            showBubble("把「\(name)」叼过来了~（配个模型我就能帮你看看）"); return
        }
        showBubble("闻闻这个「\(name)」…", sticky: true)
        let system = fullSystem
        Task { @MainActor in
            do {
                let line = try await LLM.chat(provider: p, system: system,
                    user: "主人把文件「\(name)」拖给了你。用你的性格，简短说一句你的反应，或能帮 TA 怎么处理，不超过 25 字。")
                showBubble(line)
            } catch { showBubble("（这文件我看不懂…）") }
        }
    }

    func morningGreeting() { showBubble("早上好困……要来杯咖啡吗？☕️") }
    func feedCoffee() { showBubble("咖啡！瞬间支棱起来了 ☕✨"); setState(.happy, revertAfter: 1.6); playAction(.drinkCoffee) }
    func feedWater() { showBubble("咕嘟咕嘟……谢啦老大 💧"); setState(.happy, revertAfter: 1.6) }
}
