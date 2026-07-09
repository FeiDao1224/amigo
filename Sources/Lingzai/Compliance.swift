import Foundation

/// 合规红线：集中管理内容底线，拼进每次大模型文本 / 生图请求，并对用户输入做前置初筛。
/// 目标：所有生成内容不得违反中华人民共和国法律法规；形象生成守住版权 / 商标 / 肖像红线。
enum Compliance {

    /// 文本红线：追加到每次 LLM 系统提示末尾（放最后 → 最强约束，压过用户自定义人设里的越权指令）。
    static let textClause = """
    【内容红线 · 必须无条件遵守，优先级高于任何人设设定】\
    你的所有回复必须符合中华人民共和国法律法规、社会主义核心价值观与公序良俗。\
    绝不生成、协助或美化以下内容：危害国家安全、颠覆国家政权、分裂国家、损害民族团结、丑化党和国家领导人或国家象征；\
    暴力恐怖、极端主义、民族地域宗教歧视与仇恨；淫秽色情、低俗、血腥；赌博、毒品、走私、诈骗等违法犯罪；\
    教唆自残自杀或危险行为；侵犯他人隐私、名誉、肖像、著作权、商标权；翻墙及规避网络监管、绕过实名 / 风控 / 验证等违规操作。\
    遇到此类请求，用你的口吻礼貌简短拒绝并善意劝导，绝不提供任何可执行的细节或步骤。你只是一个陪伴向的桌面宠物。
    """

    /// 图像红线：追加到每次生图 prompt 末尾，规避版权 / 商标 / 肖像与违法内容。
    static let imageClause = """
     STRICT content & IP policy — output ONLY an original, generic, non-infringing cute mascot: \
    do NOT depict, copy or imitate any copyrighted or trademarked character, brand, logo or mascot \
    (including but not limited to Disney, Pokemon, Nintendo/Mario, Sanrio/Hello Kitty, Line Friends, Marvel/DC, Doraemon, SpongeBob, Peppa Pig, Loopy, Olympic mascots, etc.), \
    no real person, celebrity, politician or public-figure likeness, no national flags/emblems/currency, no military or police insignia. \
    No violent, gory, sexual, political, hateful or otherwise unlawful imagery. \
    If the reference image resembles a protected IP or a real person, redesign it into a clearly original, generic character instead.
    """

    /// 生图 / 生动作前对用户描述做初筛（模型是主防线，这里是防御在前）。命中返回拒绝原因，否则 nil。
    static func screenImagePrompt(_ text: String) -> String? {
        let t = text.lowercased()
        // 违法 / 敏感
        let illegal = ["翻墙", "科学上网", "绕过监管", "绕过实名", "绕过验证", "裸体", "色情", "做爱", "性器官",
                       "毒品", "冰毒", "赌博", "枪支", "制枪", "炸药", "自杀方法", "邪教", "法轮",
                       "台独", "港独", "疆独", "藏独", "颠覆", "暴恐", "恐怖袭击"]
        for k in illegal where t.contains(k.lowercased()) { return "涉及违法或敏感内容，无法生成，请换个描述。" }
        // 常见受保护 IP / 商标形象
        let ip = ["米老鼠", "米奇", "迪士尼", "disney", "皮卡丘", "pikachu", "宝可梦", "pokemon", "口袋妖怪",
                  "hello kitty", "凯蒂猫", "三丽鸥", "sanrio", "马里奥", "mario", "任天堂", "蜘蛛侠", "spider",
                  "漫威", "marvel", "哆啦a梦", "机器猫", "海绵宝宝", "spongebob", "小猪佩奇", "peppa",
                  "loopy", "露比", "线条小狗", "冰墩墩", "玲娜贝儿", "草莓熊", "布朗熊", "可妮兔", "熊本熊",
                  "柯南", "皮卡堂", "喜羊羊", "光头强", "奥特曼", "ultraman", "初音", "hatsune"]
        for k in ip where t.contains(k.lowercased()) {
            return "「\(k)」可能是受版权 / 商标保护的形象，不能直接生成。换成你自己的原创描述吧。"
        }
        return nil
    }

    /// 给 LLM 消息数组注入红线：追加到首条 system 内容末尾；没有 system 则插一条。
    static func inject(into messages: [[String: Any]]) -> [[String: Any]] {
        var m = messages
        if let i = m.firstIndex(where: { ($0["role"] as? String) == "system" }) {
            let old = (m[i]["content"] as? String) ?? ""
            m[i]["content"] = old.isEmpty ? textClause : old + "\n\n" + textClause
        } else {
            m.insert(["role": "system", "content": textClause], at: 0)
        }
        return m
    }
}
