import Foundation

/// 宠物性格设计师：给大模型一套完整提示词 + 用户问卷答案 → 生成性格 CardData
enum PersonaDesigner {
    private static let metaPrompt = """
    你是一个「桌面宠物性格设计师」。根据用户的问卷回答，为一只桌面小宠物设计性格。
    严格红线：这是一只【动物宠物】，绝不是人类、不是恋人 / 亲属 / 心理咨询师；不得制造情感依赖或"只有我懂你"的叙事。
    只输出一个 JSON 对象，不要任何解释或多余文字，字段如下：
    {
      "name": "宠物名字",
      "species": "动物物种（如 猫 / 狗 / 水豚）",
      "tone": "性格与说话风格，一句话概括",
      "catchphrases": ["口头禅1", "口头禅2", "口头禅3"],
      "persona": "给另一个 AI 当 system prompt 用的完整角色设定，第二人称『你是…』，100 字以内，包含：如何称呼主人、日常态度、绝不假装人类"
    }
    """

    static func design(provider: Provider, answers: String) async throws -> CardData {
        let content = try await LLM.chat(provider: provider, system: metaPrompt,
                                         user: "问卷回答：\n\(answers)\n\n请据此设计这只宠物的性格。")
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              let data = String(content[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let card = CardData.fromLLM(obj) else {
            throw NSError(domain: "lingzai", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "没能从模型输出里解析出性格，换个模型或重试。"])
        }
        return card
    }
}
