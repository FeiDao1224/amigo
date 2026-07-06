import AppKit
import Foundation

enum PetAction: String, Codable, CaseIterable, Identifiable {
    case idleStand = "idle_stand"
    case deskWork = "desk_work"
    case drinkCoffee = "drink_coffee"
    case eatBurger = "eat_burger"
    case playPhone = "play_phone"
    case walk
    case lieDown = "lie_down"
    case sleep
    case wave
    case shocked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .idleStand: return "站立待机"
        case .deskWork: return "办公桌"
        case .drinkCoffee: return "喝咖啡"
        case .eatBurger: return "吃汉堡"
        case .playPhone: return "玩手机"
        case .walk: return "行走"
        case .lieDown: return "躺下"
        case .sleep: return "睡觉"
        case .wave: return "挥手"
        case .shocked: return "震惊"
        }
    }
}

struct PetAnimationConfig: Codable, Equatable {
    var fps: Double
    var loop: Bool
    var interruptible: Bool
    var holdLastFrame: Bool
    var frameCount: Int

    init(
        fps: Double,
        loop: Bool,
        interruptible: Bool,
        holdLastFrame: Bool = false,
        frameCount: Int
    ) {
        self.fps = fps
        self.loop = loop
        self.interruptible = interruptible
        self.holdLastFrame = holdLastFrame
        self.frameCount = frameCount
    }

    private enum CodingKeys: String, CodingKey {
        case fps, loop, interruptible, holdLastFrame, frameCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fps = try c.decode(Double.self, forKey: .fps)
        loop = try c.decode(Bool.self, forKey: .loop)
        interruptible = try c.decodeIfPresent(Bool.self, forKey: .interruptible) ?? true
        holdLastFrame = try c.decodeIfPresent(Bool.self, forKey: .holdLastFrame) ?? false
        frameCount = try c.decode(Int.self, forKey: .frameCount)
    }
}

struct PetProfile: Codable, Equatable {
    var petId: String
    var displayName: String
    var defaultAction: PetAction
    var pixelCanvasWidth: Int
    var pixelCanvasHeight: Int
    var scale: Int
    var animations: [PetAction: PetAnimationConfig]

    private enum CodingKeys: String, CodingKey {
        case petId, displayName, defaultAction, pixelCanvasWidth, pixelCanvasHeight, scale, animations
    }

    init(
        petId: String,
        displayName: String,
        defaultAction: PetAction,
        pixelCanvasWidth: Int,
        pixelCanvasHeight: Int,
        scale: Int,
        animations: [PetAction: PetAnimationConfig]
    ) {
        self.petId = petId
        self.displayName = displayName
        self.defaultAction = defaultAction
        self.pixelCanvasWidth = pixelCanvasWidth
        self.pixelCanvasHeight = pixelCanvasHeight
        self.scale = scale
        self.animations = animations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        petId = try c.decode(String.self, forKey: .petId)
        displayName = try c.decode(String.self, forKey: .displayName)
        defaultAction = try c.decode(PetAction.self, forKey: .defaultAction)
        pixelCanvasWidth = try c.decode(Int.self, forKey: .pixelCanvasWidth)
        pixelCanvasHeight = try c.decode(Int.self, forKey: .pixelCanvasHeight)
        scale = try c.decodeIfPresent(Int.self, forKey: .scale) ?? 1

        let rawAnimations = try c.decode([String: PetAnimationConfig].self, forKey: .animations)
        animations = Dictionary(
            uniqueKeysWithValues: rawAnimations.compactMap { key, value in
                guard let action = PetAction(rawValue: key) else { return nil }
                return (action, value)
            }
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(petId, forKey: .petId)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(defaultAction, forKey: .defaultAction)
        try c.encode(pixelCanvasWidth, forKey: .pixelCanvasWidth)
        try c.encode(pixelCanvasHeight, forKey: .pixelCanvasHeight)
        try c.encode(scale, forKey: .scale)
        let rawAnimations = Dictionary(uniqueKeysWithValues: animations.map { ($0.key.rawValue, $0.value) })
        try c.encode(rawAnimations, forKey: .animations)
    }
}

struct PetAnimationClip {
    let action: PetAction
    let config: PetAnimationConfig
    let frames: [NSImage]

    var isEmpty: Bool { frames.isEmpty }
}

enum PetAssetLoader {
    private static let decoder = JSONDecoder()
    private static var profileCache: [String: PetProfile] = [:]
    private static var clipCache: [String: [PetAction: PetAnimationClip]] = [:]

    static func profile(petId: String) -> PetProfile? {
        if let cached = profileCache[petId] { return cached }
        guard let url = Bundle.module.url(
            forResource: "profile",
            withExtension: "json",
            subdirectory: "Pets/\(petId)"
        ),
              let data = try? Data(contentsOf: url),
              let profile = try? decoder.decode(PetProfile.self, from: data)
        else {
            return nil
        }
        profileCache[petId] = profile
        return profile
    }

    static func clip(profile: PetProfile, action: PetAction) -> PetAnimationClip? {
        if let cached = clipCache[profile.petId]?[action] { return cached }
        guard let config = profile.animations[action] else { return nil }

        let frames = (0..<config.frameCount).compactMap { index -> NSImage? in
            let name = String(format: "frame_%03d", index)
            guard let url = Bundle.module.url(
                forResource: name,
                withExtension: "png",
                subdirectory: "Pets/\(profile.petId)/\(action.rawValue)"
            ) else {
                return nil
            }
            guard let image = NSImage(contentsOf: url) else { return nil }
            image.isTemplate = false
            return image
        }

        guard !frames.isEmpty else { return nil }
        let clip = PetAnimationClip(action: action, config: config, frames: frames)
        var petCache = clipCache[profile.petId] ?? [:]
        petCache[action] = clip
        clipCache[profile.petId] = petCache
        return clip
    }

    static func clearCache(for petId: String? = nil) {
        if let petId {
            profileCache.removeValue(forKey: petId)
            clipCache.removeValue(forKey: petId)
        } else {
            profileCache.removeAll()
            clipCache.removeAll()
        }
    }
}

@MainActor
final class PetAnimator: ObservableObject {
    @Published private(set) var profile: PetProfile?
    @Published private(set) var currentAction: PetAction = .idleStand
    @Published private(set) var currentFrame: NSImage?
    @Published private(set) var currentFrameIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false

    private var currentClip: PetAnimationClip?
    private var timer: Timer?

    deinit { timer?.invalidate() }

    func loadPet(_ petId: String) {
        stopTimer()
        currentFrame = nil
        currentFrameIndex = 0
        currentClip = nil
        guard petId != "cat", let profile = PetAssetLoader.profile(petId: petId) else {
            self.profile = nil
            return
        }
        self.profile = profile
        play(profile.defaultAction, force: true)
    }

    func play(_ action: PetAction, force: Bool = false) {
        guard let profile else { return }
        if !force, let currentClip, !currentClip.config.interruptible, isPlaying {
            return
        }

        let requested = PetAssetLoader.clip(profile: profile, action: action)
        let fallback = PetAssetLoader.clip(profile: profile, action: profile.defaultAction)
        guard let clip = requested ?? fallback else {
            stopTimer()
            currentFrame = nil
            return
        }

        currentClip = clip
        currentAction = clip.action
        currentFrameIndex = 0
        currentFrame = clip.frames.first
        scheduleTimer(for: clip)
    }

    func pause() {
        stopTimer()
        isPlaying = false
    }

    func resume() {
        guard let currentClip else { return }
        scheduleTimer(for: currentClip)
    }

    func playRandomCompanionAction() {
        let candidates: [PetAction] = [.idleStand, .deskWork, .playPhone, .drinkCoffee, .eatBurger, .wave]
        play(candidates.randomElement() ?? .idleStand)
    }

    func playState(_ state: PetState) {
        switch state {
        case .idle: play(.idleStand)
        case .talk: play(.wave)
        case .happy: play(.wave)
        case .shocked: play(.shocked, force: true)
        case .bored: play(.playPhone)
        case .sleep: play(.sleep)
        case .dragged: play(.walk, force: true)
        case .hop: play(.wave)
        case .wiggle: play(.idleStand)
        case .stretch: play(.lieDown)
        case .lean: play(.deskWork)
        }
    }

    private func scheduleTimer(for clip: PetAnimationClip) {
        stopTimer()
        guard clip.frames.count > 1, clip.config.fps > 0 else {
            isPlaying = false
            return
        }
        isPlaying = true
        let interval = 1.0 / clip.config.fps
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advanceFrame() {
        guard let clip = currentClip, !clip.frames.isEmpty else {
            stopTimer()
            currentFrame = nil
            return
        }

        let next = currentFrameIndex + 1
        if next < clip.frames.count {
            currentFrameIndex = next
            currentFrame = clip.frames[next]
            return
        }

        if clip.config.loop {
            currentFrameIndex = 0
            currentFrame = clip.frames[0]
        } else if clip.config.holdLastFrame {
            currentFrameIndex = clip.frames.count - 1
            currentFrame = clip.frames[currentFrameIndex]
            stopTimer()
            isPlaying = false
        } else if let profile {
            play(profile.defaultAction, force: true)
        } else {
            stopTimer()
            isPlaying = false
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }
}
