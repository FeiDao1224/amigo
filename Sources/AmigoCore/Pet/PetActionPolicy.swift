import Foundation

/// 桌宠该播哪套动作：纯函数，不碰窗口 / 系统查询。
/// 采样前台应用和闲置时长仍由 AppDelegate 做，结果作为输入传进来。
enum PetActionPolicy {
    struct Input: Equatable {
        var now: Date
        var oneShotKey: String
        var oneShotUntil: Date?
        var waitingReply: Bool
        var chatting: Bool
        var dragging: Bool
        var dragSpeed: Double
        var behaviorDriven: Bool
        var stealth: Bool
        var idleLong: Bool
        var frontActive: Bool
        var mapChat: String
        var mapDrag: String
        var activeAction: String
    }

    struct Output: Equatable {
        var action: String
        var speed: Double
        var resetFacing: Bool
        var fallbackMotion: Int
        var clearOneShot: Bool
    }

    static func choose(_ input: Input) -> Output {
        if let until = input.oneShotUntil, input.now < until {
            return Output(action: input.oneShotKey, speed: 1, resetFacing: false, fallbackMotion: 0, clearOneShot: false)
        }
        return decide(input, clearOneShot: input.oneShotUntil != nil)
    }

    /// 一次性动作已过期或本来就没有时，按对话 / 隐身 / 拖动 / 闲置决定。
    private static func decide(_ input: Input, clearOneShot: Bool) -> Output {
        if input.waitingReply || input.chatting {
            return Output(action: input.mapChat, speed: 1, resetFacing: true, fallbackMotion: 0, clearOneShot: clearOneShot)
        }
        guard input.behaviorDriven, !input.stealth else {
            return Output(action: input.activeAction, speed: 1, resetFacing: true, fallbackMotion: 0, clearOneShot: clearOneShot)
        }
        if input.dragging {
            let speed = min(2.4, max(1.0, input.dragSpeed / 260))
            return Output(action: input.mapDrag, speed: speed, resetFacing: false, fallbackMotion: 1, clearOneShot: clearOneShot)
        }
        if input.idleLong {
            return Output(action: "sleep", speed: 1, resetFacing: true, fallbackMotion: 0, clearOneShot: clearOneShot)
        }
        if input.frontActive {
            return Output(action: "work", speed: 1, resetFacing: true, fallbackMotion: 0, clearOneShot: clearOneShot)
        }
        return Output(action: input.activeAction, speed: 1, resetFacing: true, fallbackMotion: 0, clearOneShot: clearOneShot)
    }
}
