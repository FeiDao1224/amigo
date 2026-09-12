import Foundation

/// 桌宠当下的心情。不对应收费动作帧，只影响气泡、朝向和设置页展示。
enum PetMood: String, Codable, CaseIterable {
    case happy, calm, missing, sulky, sleepy

    var title: String {
        switch self {
        case .happy: return "开心"
        case .calm: return "待着"
        case .missing: return "想你"
        case .sulky: return "委屈"
        case .sleepy: return "犯困"
        }
    }
}

enum CompanionEvent: String, Equatable {
    case pet, feed, chat, tick, returned
}

/// 当天被看见的次数。不是饥饿条。
struct DayLog: Equatable, Codable {
    var day: String = ""
    var pets: Int = 0
    var feeds: Int = 0
    var chats: Int = 0

    var touched: Bool { pets + feeds + chats > 0 }
}

/// 它自己写下的一天。最多留在本机，给人翻，不催你补打卡。
struct DiaryEntry: Equatable, Codable, Identifiable {
    var day: String
    var line: String
    var pets: Int = 0
    var feeds: Int = 0
    var chats: Int = 0

    var id: String { day }
    var touched: Bool { pets + feeds + chats > 0 }
}

/// 陪伴进度：亲密度会随互动涨、被冷落掉，全部只存本机。
struct CompanionSnapshot: Equatable, Codable {
    var affection: Int = 36
    var mood: PetMood = .calm
    var daysTogether: Int = 1
    var lastTouchAt: Date? = nil
    var lastDecayAt: Date? = nil
    var lastVisitDay: String? = nil
    var today: DayLog = DayLog()
    var diary: [DiaryEntry] = []

    enum CodingKeys: String, CodingKey {
        case affection, mood, daysTogether, lastTouchAt, lastDecayAt, lastVisitDay, today, diary
    }

    init(
        affection: Int = 36,
        mood: PetMood = .calm,
        daysTogether: Int = 1,
        lastTouchAt: Date? = nil,
        lastDecayAt: Date? = nil,
        lastVisitDay: String? = nil,
        today: DayLog = DayLog(),
        diary: [DiaryEntry] = []
    ) {
        self.affection = affection
        self.mood = mood
        self.daysTogether = daysTogether
        self.lastTouchAt = lastTouchAt
        self.lastDecayAt = lastDecayAt
        self.lastVisitDay = lastVisitDay
        self.today = today
        self.diary = diary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        affection = try c.decodeIfPresent(Int.self, forKey: .affection) ?? 36
        mood = try c.decodeIfPresent(PetMood.self, forKey: .mood) ?? .calm
        daysTogether = try c.decodeIfPresent(Int.self, forKey: .daysTogether) ?? 1
        lastTouchAt = try c.decodeIfPresent(Date.self, forKey: .lastTouchAt)
        lastDecayAt = try c.decodeIfPresent(Date.self, forKey: .lastDecayAt)
        lastVisitDay = try c.decodeIfPresent(String.self, forKey: .lastVisitDay)
        today = try c.decodeIfPresent(DayLog.self, forKey: .today) ?? DayLog()
        diary = try c.decodeIfPresent([DiaryEntry].self, forKey: .diary) ?? []
    }
}

enum CompanionPolicy {
    static let diaryKeep = 14

    static func apply(_ raw: CompanionSnapshot, event: CompanionEvent, now: Date, hour: Int, idleSeconds: Double) -> (CompanionSnapshot, String?) {
        var s = raw
        s.affection = min(100, max(0, s.affection))
        rollDay(&s, now: now)

        switch event {
        case .pet:
            s.affection = min(100, s.affection + 8)
            s.lastTouchAt = now
            s.today.pets += 1
            s.mood = .happy
            return (s, line(.pet, s.mood))
        case .feed:
            s.affection = min(100, s.affection + 12)
            s.lastTouchAt = now
            s.today.feeds += 1
            s.mood = .happy
            return (s, line(.feed, s.mood))
        case .chat:
            s.affection = min(100, s.affection + 4)
            s.lastTouchAt = now
            s.today.chats += 1
            if s.mood == .missing || s.mood == .sulky { s.mood = .happy }
            else { s.mood = mood(s, now: now, hour: hour, idleSeconds: idleSeconds) }
            return (s, nil)
        case .tick:
            decay(&s, now: now)
            s.mood = mood(s, now: now, hour: hour, idleSeconds: idleSeconds)
            return (s, nil)
        case .returned:
            decay(&s, now: now)
            s.mood = mood(s, now: now, hour: hour, idleSeconds: 0)
            return (s, line(.returned, s.mood))
        }
    }

    static func hello(_ s: CompanionSnapshot, now: Date, hour: Int) -> String {
        if let y = s.diary.first, isYesterday(y.day, now: now) {
            if !y.touched { return "昨天你没过来。今天也待一会儿就好。" }
            return "昨天你来过。我还记得。"
        }
        if s.mood == .missing || s.mood == .sulky { return line(.returned, s.mood) }
        if (5...10).contains(hour) { return "又见面了……今天也待一会儿就好。" }
        if hour >= 23 || hour < 5 { return "这么晚还在，我不吵你，就坐旁边。" }
        return line(.tick, s.mood)
    }

    static func murmur(_ mood: PetMood) -> String { line(.tick, mood) }

    static func todayCaption(_ log: DayLog) -> String {
        log.touched ? "今天你来过。" : "今天还没理我。我在。"
    }

    static func todayDetail(_ log: DayLog) -> String {
        if !log.touched { return "不是任务。你来了，我就记一句。" }
        var bits: [String] = []
        if log.pets > 0 { bits.append("摸摸 \(log.pets)") }
        if log.feeds > 0 { bits.append("喂食 \(log.feeds)") }
        if log.chats > 0 { bits.append("说过话") }
        return bits.joined(separator: " · ")
    }

    static func diaryLine(_ log: DayLog) -> String {
        if !log.touched { return "你没来。我自己待着。" }
        if log.feeds > 0 && log.pets > 0 { return "你摸了我，还喂了一口。我记下了。" }
        if log.feeds > 0 { return "你喂了我。胃里还是暖的。" }
        if log.chats > 0 && log.pets == 0 { return "你跟我说了话。这就够了。" }
        if log.pets >= 5 { return "你摸了好多下。头毛全乱了。" }
        return "你来过。我就记这一句。"
    }

    static func diarySpeak(_ s: CompanionSnapshot) -> String {
        if s.today.touched { return todayCaption(s.today) }
        if let y = s.diary.first { return y.line }
        return "今天还没写。你在，我就在。"
    }

    static func displayDay(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return day }
        return "\(m)月\(d)日"
    }

    static func dayKey(_ now: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let y = c.year ?? 0, m = c.month ?? 0, d = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func isYesterday(_ day: String, now: Date) -> Bool {
        guard let y = Calendar.current.date(byAdding: .day, value: -1, to: now) else { return false }
        return day == dayKey(y)
    }

    private static func rollDay(_ s: inout CompanionSnapshot, now: Date) {
        let day = dayKey(now)
        if s.today.day == day {
            s.lastVisitDay = day
            return
        }
        if !s.today.day.isEmpty {
            let entry = DiaryEntry(
                day: s.today.day,
                line: diaryLine(s.today),
                pets: s.today.pets,
                feeds: s.today.feeds,
                chats: s.today.chats
            )
            s.diary.insert(entry, at: 0)
            if s.diary.count > diaryKeep { s.diary.removeSubrange(diaryKeep...) }
        }
        if s.lastVisitDay != nil, s.lastVisitDay != day { s.daysTogether += 1 }
        s.lastVisitDay = day
        s.today = DayLog(day: day)
    }

    private static func decay(_ s: inout CompanionSnapshot, now: Date) {
        guard let last = s.lastTouchAt else { return }
        let ignored = now.timeIntervalSince(last)
        guard ignored > 2 * 3600 else { return }
        let anchor = s.lastDecayAt ?? last
        let steps = Int(now.timeIntervalSince(anchor) / (20 * 60))
        guard steps > 0 else { return }
        s.affection = max(0, s.affection - steps)
        s.lastDecayAt = now
    }

    static func mood(_ s: CompanionSnapshot, now: Date, hour: Int, idleSeconds: Double) -> PetMood {
        let touchedAgo = s.lastTouchAt.map { now.timeIntervalSince($0) } ?? 10_000
        if touchedAgo < 4 * 60 { return .happy }
        if (hour >= 23 || hour < 6) && idleSeconds > 90 { return .sleepy }
        if idleSeconds > 180 { return .sleepy }
        if s.affection < 20 || touchedAgo > 10 * 3600 { return .sulky }
        if touchedAgo > 3 * 3600 { return .missing }
        if s.affection >= 70 && touchedAgo < 3600 { return .happy }
        return .calm
    }

    private static func line(_ event: CompanionEvent, _ mood: PetMood) -> String {
        switch event {
        case .pet:
            return ["唔……再摸一下。", "头毛都被你摸乱了。", "嗯，这样挺好。"].randomElement()!
        case .feed:
            return ["收下了。才不是因为想吃。", "……还有吗。", "嗯，胃里暖了一点。"].randomElement()!
        case .returned:
            switch mood {
            case .sulky: return "你去哪了。我又没地方去。"
            case .missing: return "你终于看我了。"
            default: return "回来啦。我一直在。"
            }
        case .chat, .tick:
            switch mood {
            case .happy: return ["今天有点喜欢待在这儿。", "你在我就够了。", "……哼歌给你听。"].randomElement()!
            case .calm: return ["我就坐这儿。", "不吵你。", "……在。"].randomElement()!
            case .missing: return ["你忙的时候，我会自己数窗户。", "想起你了。", "过来一下就行。"].randomElement()!
            case .sulky: return ["当我不存在也可以。", "……转过去了。", "才没有等你。"].randomElement()!
            case .sleepy: return ["眼皮在打架。", "你继续，我眯一会儿。", "好困，但还想挨着你。"].randomElement()!
            }
        }
    }
}
