// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

@main
struct EssayRevisionProbe {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let credentials = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent(".private/BootstrapCredentials.plist")), format: nil) as! [String:String]
        var preferences = ChatPreferences(); preferences.essayMode = true; preferences.answerLength = .short; preferences.contextDepth = .none
        let assignment = "以《那盏灯》为题写约800字初三考场作文。素材：初三考试失利，我和父亲闹别扭；晚自习后下雨，父亲仍在校门口的灯下等我，他将伞向我倾斜，自己的袖子湿透。我从不耐烦到主动靠近他。不要新增疾病、死亡、离异或获奖；父亲不是学生，动作和书包归属要连续。开头明确点题并引出下文，语言较华丽但符合初三；最后2–3段逐层升华，写感悟、主旨与立意。只给标题和全文。"
        let client = MiMoClient()
        let key = credentials["DeepSeekAPIKey"]!
        let original = try await collect(client.reply(key: key, model: "deepseek-flash", messages: ChatContext.messages(history: [], prompt: assignment, preferences: preferences), thinking: false, preferences: preferences, provider: .deepSeek))
        try original.text.write(to: root.appendingPathComponent("Verification/v1.4-essay-sample.txt"), atomically: true, encoding: .utf8)
        let prompt = EssayRevision.ending.prompt(original: original.text, assignment: assignment, target: 800, direction: "最后三段依次写理解父亲、理解亲情、回到那盏灯明确点题；不写成人化哲理。")
        let revised = try await collect(client.reply(key: key, model: "deepseek-flash", messages: ChatContext.messages(history: [], prompt: prompt, preferences: preferences), thinking: false, preferences: preferences, provider: .deepSeek))
        try revised.text.write(to: root.appendingPathComponent("Verification/v1.4-essay-revised-ending.txt"), atomically: true, encoding: .utf8)
        let report: [String: Any] = ["originalComplete": original.done && original.reason == "stop", "revisionComplete": revised.done && revised.reason == "stop", "originalBodyCount": EssayDocument(original.text).wordCount, "revisedBodyCount": EssayDocument(revised.text).wordCount, "originalParagraphs": EssayDocument(original.text).paragraphs.count, "revisedParagraphs": EssayDocument(revised.text).paragraphs.count, "contextDisabled": true, "originalSuppliedInRevision": prompt.contains(original.text), "titlePreserved": EssayDocument(revised.text).title?.contains("那盏灯") == true, "keyLogged": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("Verification/v1.4-live-writing.json"))
        print("Original and revised essay received; credential not logged.")
    }
    static func collect(_ events: AsyncThrowingStream<StreamEvent, Error>) async throws -> (text: String, done: Bool, reason: String?) {
        var text = "", done = false; var reason: String?
        for try await event in events {
            switch event { case .text(let part): text += part; case .done: done = true; case .finished(let value): reason = value; default: break }
        }
        return (text, done, reason)
    }
}
