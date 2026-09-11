import SwiftUI
import AppKit

enum PetState { case idle, talk, dragged }

/// 高频动画状态：只被宠物窗观察，不连累设置窗
@MainActor
final class PetRuntime: ObservableObject {
    @Published var bubbleText: String = ""
    @Published var petState: PetState = .idle
    @Published var chatting = false                     // 下方输入框展开中
    @Published var characterImageName: String = "penguin"
    @Published var actionFrames: [NSImage] = []         // 当前动作的 AI 帧：非空则优先循环播放
    @Published var actionFPS: Double = 3
    @Published var speedFactor: Double = 1.0            // 播放倍速（拖动越快越大）
    @Published var moveMotion: Int = 0                  // 0=无 1=走 2=跑（没生成对应动作时的程序位移兜底）
    @Published var waitingReply = false                 // 发消息后等模型返回：显示"打电话"
    @Published var facingLeft = false                   // 朝向：往左走时水平翻转
    @Published var oneShotUntil: Date?                  // 一次性播放某动作(点击触发)到某时刻
    var oneShotKey = ""
    func oneShot(_ key: String, seconds: Double = 2.5) { oneShotKey = key; oneShotUntil = Date().addingTimeInterval(seconds) }

    private var currentActionKey = ""
    private var framesCache: [String: [NSImage]] = [:]

    /// 切到某动作（按当前形象加载，带缓存，可高频调用）。没生成则**保留当前帧** + fallbackMotion 程序位移。
    func showAction(_ key: String, fallbackMotion: Int = 0) {
        let cacheKey = "\(characterImageName)/\(key)"
        let frames = framesCache[cacheKey] ?? {
            let f = SpriteGen.loadFrames(character: characterImageName, action: key); framesCache[cacheKey] = f; return f
        }()
        if frames.isEmpty {
            if moveMotion != fallbackMotion { moveMotion = fallbackMotion }
            return
        }
        if moveMotion != 0 { moveMotion = 0 }
        guard cacheKey != currentActionKey else { return }
        currentActionKey = cacheKey
        actionFrames = frames
        // 帧率 = 帧数 / 目标循环时长 → 4 帧或 16 帧都同样从容（上限 20fps=显示刷新率）
        let loop = PetAnimAction(rawValue: key)?.loopSeconds ?? 1.6
        actionFPS = min(20, max(1, Double(frames.count) / loop))
    }
    /// 生成/切形象后刷新缓存，下一帧重新加载
    func invalidateActions() { framesCache.removeAll(); currentActionKey = ""; moveMotion = 0; actionFrames = [] }

    private var stateWork: DispatchWorkItem?
    func setState(_ s: PetState, revertAfter: TimeInterval? = nil) {
        petState = s
        stateWork?.cancel()
        guard let r = revertAfter else { return }
        let w = DispatchWorkItem { [weak self] in self?.petState = .idle }
        stateWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + r, execute: w)
    }

    func setCharacter(_ id: String) {
        characterImageName = id
        invalidateActions()          // 换形象 → 重新加载该形象的动作帧
    }

    var activeProvider: (() -> Provider?)?
    var activeCard: (() -> CardData)?
    var nudgeUseLLM: () -> Bool = { false }
    var memoryContext: () -> String = { "" }
    var isStealth: () -> Bool = { false }
    var senseFrontApp: () -> Bool = { true }

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
        let w = DispatchWorkItem { [weak self] in withAnimation { self?.bubbleText = "" } }
        clearWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: w)
    }

    private var card: CardData { activeCard?() ?? .default }
    private var fullSystem: String {
        [card.systemPrompt, memoryContext(), SystemInfo.context(includeFrontApp: senseFrontApp())].filter { !$0.isEmpty }.joined(separator: "\n\n")
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
                NSLog("Amigo LLM error: \(error.localizedDescription)")
            }
        }
    }

    /// 主动督促：开关开 + 有模型时用 AI 生成有性格的一句，否则用内置文案
    func nudge(situation: String, fallback: String) {
        guard !isStealth() else { return }
        guard nudgeUseLLM(), let p = activeProvider?(), !p.apiKey.isEmpty, !p.baseUrl.isEmpty else {
            showBubble(fallback); return
        }
        let system = fullSystem
        Task { @MainActor in
            do {
                let line = try await LLM.chat(provider: p, system: system,
                    user: "现在的情况：\(situation)。用你的性格，主动对主人说一句简短的提醒或关心，不超过 25 字，别解释。")
                guard !isStealth() else { return }
                showBubble(line)
            } catch { if !isStealth() { showBubble(fallback) } }
        }
    }

    func morningGreeting() { showBubble("早上好困……要来杯咖啡吗？") }
}
