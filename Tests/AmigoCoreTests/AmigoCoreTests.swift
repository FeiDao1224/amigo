import Foundation
import Testing
@testable import AmigoCore

struct ComplianceTests {
    @Test func injectAppendsToExistingSystem() {
        let out = Compliance.inject(into: [
            ["role": "system", "content": "你叫咕咕。"],
            ["role": "user", "content": "hi"],
        ])
        let sys = out[0]["content"] as? String ?? ""
        #expect(out.count == 2)
        #expect(sys.contains("你叫咕咕。"))
        #expect(sys.contains("内容红线"))
    }

    @Test func injectInsertsSystemWhenMissing() {
        let out = Compliance.inject(into: [["role": "user", "content": "hi"]])
        #expect(out[0]["role"] as? String == "system")
        #expect((out[0]["content"] as? String)?.contains("内容红线") == true)
    }

    @Test(arguments: ["皮卡丘", "disney", "翻墙", "裸体"])
    func screenImagePromptRejects(_ keyword: String) {
        #expect(Compliance.screenImagePrompt("请生成\(keyword)") != nil)
    }

    @Test func screenImagePromptAllowsOriginal() {
        #expect(Compliance.screenImagePrompt("圆滚滚的原创小企鹅桌宠") == nil)
    }
}

struct ProviderImportTests {
    @Test func fromJSON() throws {
        let raw = #"{"name":"智谱","baseUrl":"https://api.example.com/v1","model":"glm-4","apiKey":"sk-testkeytestkeytest"}"#
        let p = try #require(Provider.fromImport(raw))
        #expect(p.name == "智谱")
        #expect(p.baseUrl == "https://api.example.com/v1")
        #expect(p.model == "glm-4")
        #expect(p.apiKey == "sk-testkeytestkeytest")
    }

    @Test func fromURLQuery() throws {
        let p = try #require(Provider.fromImport("amigo://import?base_url=https://api.example.com/v1&model=glm-4&api_key=sk-aaaaaaaaaaaaaaaa"))
        #expect(p.baseUrl == "https://api.example.com/v1")
        #expect(p.model == "glm-4")
        #expect(p.apiKey == "sk-aaaaaaaaaaaaaaaa")
    }

    @Test func fromTomlSnippet() throws {
        let raw = """
        base_url = "https://relay.example.com/v1"
        model = "gpt-4o-mini"
        OPENAI_API_KEY = "sk-bbbbbbbbbbbbbbbb"
        """
        let p = try #require(Provider.fromImport(raw))
        #expect(p.baseUrl == "https://relay.example.com/v1")
        #expect(p.model == "gpt-4o-mini")
    }

    @Test func emptyAndGarbage() {
        #expect(Provider.fromImport("") == nil)
        #expect(Provider.fromImport("hello world") == nil)
    }
}

struct ConfigStoreTests {
    @Test func missingFieldsKeepDefaults() throws {
        let data = #"{"character":"cow","stealth":true}"#.data(using: .utf8)!
        let cfg = ConfigStore.decode(data)
        #expect(cfg.character == "cow")
        #expect(cfg.stealth == true)
        #expect(cfg.followWindow == true)
        #expect(cfg.autoMemory == false)
        #expect(cfg.clickDouble == "chat")
        #expect(cfg.companionChat == true)
        #expect(cfg.companion.affection == 36)
        #expect(cfg.companion.mood == .calm)
        #expect(cfg.companion.today.pets == 0)
        #expect(cfg.companion.diary.isEmpty)
    }

    @Test func oldCompanionJSONKeepsAffection() throws {
        let data = #"{"character":"cow","companion":{"affection":40,"mood":"happy","daysTogether":3}}"#.data(using: .utf8)!
        let cfg = ConfigStore.decode(data)
        #expect(cfg.character == "cow")
        #expect(cfg.companion.affection == 40)
        #expect(cfg.companion.mood == .happy)
        #expect(cfg.companion.daysTogether == 3)
        #expect(cfg.companion.today.day.isEmpty)
        #expect(cfg.companion.diary.isEmpty)
    }

    @Test func invalidJSONFallsBackToDefault() {
        let cfg = ConfigStore.decode(Data("not-json".utf8))
        #expect(cfg.character == "penguin")
        #expect(cfg.providers.isEmpty)
    }

    @Test func roundTripPreservesKey() throws {
        var cfg = Config()
        cfg.providers = [Provider(name: "t", baseUrl: "https://x.example/v1", model: "m", apiKey: "sk-secretsecretsecret")]
        cfg.activeId = cfg.providers[0].id
        let data = try JSONEncoder().encode(cfg)
        let back = ConfigStore.decode(data)
        #expect(back.providers.first?.apiKey == "sk-secretsecretsecret")
        #expect(back.activeId == cfg.activeId)
    }
}

struct MemoryInferenceTests {
    @Test func parsesArray() {
        let items = MemoryInference.parse("""
        这是一些废话 [{"content":"在做Amigo","category":"项目"}]
        """)
        #expect(items.count == 1)
        #expect(items[0].content == "在做Amigo")
        #expect(items[0].category == "项目")
    }

    @Test func reversedBracketsDoNotTrap() {
        #expect(MemoryInference.parse("][").isEmpty)
        #expect(MemoryInference.parse("没有记忆").isEmpty)
        #expect(MemoryInference.parse("[]").isEmpty)
    }

    @Test func missingCategoryDefaults() {
        let items = MemoryInference.parse(#"[{"content":"喜欢安静"}]"#)
        #expect(items.first?.category == "其它")
    }
}

struct PetActionPolicyTests {
    private func base(
        oneShotUntil: Date? = nil,
        oneShotKey: String = "think",
        waitingReply: Bool = false,
        chatting: Bool = false,
        dragging: Bool = false,
        dragSpeed: Double = 0,
        behaviorDriven: Bool = true,
        stealth: Bool = false,
        idleLong: Bool = false,
        frontActive: Bool = false
    ) -> PetActionPolicy.Input {
        .init(
            now: Date(timeIntervalSince1970: 1_000),
            oneShotKey: oneShotKey,
            oneShotUntil: oneShotUntil,
            waitingReply: waitingReply,
            chatting: chatting,
            dragging: dragging,
            dragSpeed: dragSpeed,
            behaviorDriven: behaviorDriven,
            stealth: stealth,
            idleLong: idleLong,
            frontActive: frontActive,
            mapChat: "phone",
            mapDrag: "walk",
            activeAction: "idle"
        )
    }

    @Test func oneShotWinsWhileActive() {
        let until = Date(timeIntervalSince1970: 2_000)
        let out = PetActionPolicy.choose(base(oneShotUntil: until))
        #expect(out.action == "think")
        #expect(out.clearOneShot == false)
        #expect(out.resetFacing == false)
    }

    @Test func expiredOneShotFallsThroughToIdle() {
        let until = Date(timeIntervalSince1970: 10)
        let out = PetActionPolicy.choose(base(oneShotUntil: until))
        #expect(out.clearOneShot == true)
        #expect(out.action == "idle")
        #expect(out.resetFacing == true)
    }

    @Test func chatMapsToPhone() {
        #expect(PetActionPolicy.choose(base(chatting: true)).action == "phone")
        #expect(PetActionPolicy.choose(base(waitingReply: true)).action == "phone")
    }

    @Test func stealthUsesDefaultAction() {
        let out = PetActionPolicy.choose(base(stealth: true, idleLong: true, frontActive: true))
        #expect(out.action == "idle")
    }

    @Test func idleSleepBeatsFrontWork() {
        let out = PetActionPolicy.choose(base(idleLong: true, frontActive: true))
        #expect(out.action == "sleep")
    }

    @Test func frontWorkWhenNotIdle() {
        #expect(PetActionPolicy.choose(base(frontActive: true)).action == "work")
    }

    @Test func dragSpeedClamped() {
        let slow = PetActionPolicy.choose(base(dragging: true, dragSpeed: 0))
        #expect(slow.action == "walk")
        #expect(slow.speed == 1.0)
        #expect(slow.resetFacing == false)
        let fast = PetActionPolicy.choose(base(dragging: true, dragSpeed: 10_000))
        #expect(fast.speed == 2.4)
        #expect(fast.fallbackMotion == 1)
    }
}

struct CompanionPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func petRaisesAffectionAndMakesHappy() {
        let s = CompanionSnapshot(affection: 20, mood: .sulky)
        let (next, line) = CompanionPolicy.apply(s, event: .pet, now: now, hour: 14, idleSeconds: 0)
        #expect(next.affection == 28)
        #expect(next.mood == .happy)
        #expect(next.lastTouchAt == now)
        #expect(line != nil && !(line ?? "").isEmpty)
    }

    @Test func feedRaisesMoreThanPet() {
        let s = CompanionSnapshot(affection: 20)
        let (pet, _) = CompanionPolicy.apply(s, event: .pet, now: now, hour: 14, idleSeconds: 0)
        let (feed, line) = CompanionPolicy.apply(s, event: .feed, now: now, hour: 14, idleSeconds: 0)
        #expect(feed.affection == pet.affection + 4)
        #expect(feed.mood == .happy)
        #expect(line != nil)
    }

    @Test func chatComfortsSulkyWithoutLine() {
        let s = CompanionSnapshot(affection: 10, mood: .sulky, lastTouchAt: now.addingTimeInterval(-12 * 3600))
        let (next, line) = CompanionPolicy.apply(s, event: .chat, now: now, hour: 14, idleSeconds: 0)
        #expect(next.affection == 14)
        #expect(next.mood == .happy)
        #expect(line == nil)
    }

    @Test func decayAfterTwoHours() {
        let touch = now.addingTimeInterval(-3 * 3600)
        let s = CompanionSnapshot(affection: 50, lastTouchAt: touch, lastDecayAt: touch)
        let (next, _) = CompanionPolicy.apply(s, event: .tick, now: now, hour: 14, idleSeconds: 10)
        #expect(next.affection == 41)
    }

    @Test func noDecayWithinTwoHours() {
        let s = CompanionSnapshot(affection: 50, lastTouchAt: now.addingTimeInterval(-90 * 60))
        let (next, _) = CompanionPolicy.apply(s, event: .tick, now: now, hour: 14, idleSeconds: 10)
        #expect(next.affection == 50)
    }

    @Test func moodMissingWhenIgnored() {
        let s = CompanionSnapshot(affection: 40, lastTouchAt: now.addingTimeInterval(-4 * 3600))
        #expect(CompanionPolicy.mood(s, now: now, hour: 14, idleSeconds: 10) == .missing)
    }

    @Test func moodSulkyWhenAffectionLow() {
        let s = CompanionSnapshot(affection: 10, lastTouchAt: now.addingTimeInterval(-20 * 60))
        #expect(CompanionPolicy.mood(s, now: now, hour: 14, idleSeconds: 10) == .sulky)
    }

    @Test func nightIdleIsSleepy() {
        let s = CompanionSnapshot(affection: 50, lastTouchAt: now.addingTimeInterval(-20 * 60))
        #expect(CompanionPolicy.mood(s, now: now, hour: 1, idleSeconds: 120) == .sleepy)
    }

    @Test func returnUsesSulkyLine() {
        let s = CompanionSnapshot(affection: 10, mood: .sulky, lastTouchAt: now.addingTimeInterval(-12 * 3600))
        let (next, line) = CompanionPolicy.apply(s, event: .returned, now: now, hour: 14, idleSeconds: 0)
        #expect(next.mood == .sulky)
        #expect(line == "你去哪了。我又没地方去。")
    }

    @Test func firstVisitStampsDayWithoutIncrement() {
        let s = CompanionSnapshot(daysTogether: 1, lastVisitDay: nil)
        let (next, _) = CompanionPolicy.apply(s, event: .tick, now: now, hour: 14, idleSeconds: 0)
        #expect(next.daysTogether == 1)
        #expect(next.lastVisitDay != nil)
    }

    @Test func newDayIncrementsTogether() {
        let s = CompanionSnapshot(daysTogether: 3, lastVisitDay: "2000-01-01")
        let (next, _) = CompanionPolicy.apply(s, event: .tick, now: now, hour: 14, idleSeconds: 0)
        #expect(next.daysTogether == 4)
    }

    @Test func helloAtNightStaysQuiet() {
        let line = CompanionPolicy.hello(CompanionSnapshot(mood: .calm), now: now, hour: 1)
        #expect(line.contains("晚") || line.contains("旁边"))
    }

    @Test func petCountsAsToday() {
        let (next, _) = CompanionPolicy.apply(CompanionSnapshot(), event: .pet, now: now, hour: 14, idleSeconds: 0)
        #expect(next.today.day == CompanionPolicy.dayKey(now))
        #expect(next.today.pets == 1)
        #expect(next.today.touched)
    }

    @Test func newDaySealsYesterday() {
        let yesterday = DayLog(day: "2000-01-01", pets: 2, feeds: 1)
        let s = CompanionSnapshot(today: yesterday)
        let (next, _) = CompanionPolicy.apply(s, event: .tick, now: now, hour: 14, idleSeconds: 0)
        #expect(next.today.day == CompanionPolicy.dayKey(now))
        #expect(next.today.pets == 0)
        #expect(next.diary.first?.day == "2000-01-01")
        #expect(next.diary.first?.pets == 2)
        #expect(next.diary.first?.line == "你摸了我，还喂了一口。我记下了。")
    }

    @Test func emptyDaySealsQuietLine() {
        #expect(CompanionPolicy.diaryLine(DayLog(day: "2000-01-01")) == "你没来。我自己待着。")
        #expect(CompanionPolicy.todayCaption(DayLog(day: "x")) == "今天还没理我。我在。")
        #expect(CompanionPolicy.todayCaption(DayLog(day: "x", pets: 1)) == "今天你来过。")
    }

    @Test func helloMentionsYesterdayVisit() {
        let y = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let s = CompanionSnapshot(
            mood: .calm,
            diary: [DiaryEntry(day: CompanionPolicy.dayKey(y), line: "你来过。我就记这一句。", pets: 1)]
        )
        #expect(CompanionPolicy.hello(s, now: now, hour: 9) == "昨天你来过。我还记得。")
    }

    @Test func diaryKeepsFourteenDays() {
        let old = (0..<14).map { DiaryEntry(day: String(format: "1999-01-%02d", $0 + 1), line: "x") }
        let s = CompanionSnapshot(today: DayLog(day: "2000-01-01", pets: 1), diary: old)
        let (next, _) = CompanionPolicy.apply(s, event: .tick, now: now, hour: 14, idleSeconds: 0)
        #expect(next.diary.count == 14)
        #expect(next.diary.first?.day == "2000-01-01")
        #expect(next.diary.last?.day == "1999-01-13")
    }
}
