// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

@main
struct LiveProbe {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let keyData = try Data(contentsOf: root.appendingPathComponent(".private/BootstrapCredentials.plist"))
        let config = try PropertyListSerialization.propertyList(from: keyData, format: nil) as! [String: String]
        let key = config["MiMoAPIKey"]!
        let client = MiMoClient()
        let models = try await client.models(key: key)
        let primary = MiMoModel.preferred(in: models)!
        let secondary = models.first(where: { $0.id == "mimo-v2.5" && $0.id != primary })?.id ??
            models.first(where: { $0.id != primary })!.id
        var history: [ChatMessage] = []
        var probes: [[String: Any]] = []
        for (model, prompt) in [(primary, "请只回复：腕聊已连接。"),
                                 (secondary, "上一条我让你回复哪五个字？只回答这五个字，不要标点。")] {
            let stream = try client.reply(key: key, model: model,
                messages: ChatContext.messages(history: history, prompt: prompt), thinking: false)
            var answer = ""
            var chunks = 0
            var finish: String?
            var done = false
            for try await event in stream {
                switch event {
                case .text(let text): answer += text; chunks += 1
                case .finished(let reason): finish = reason
                case .done: done = true
                case .thinking, .sources, .searchFailed: break
                }
            }
            guard answer.contains("腕聊已连接"), done, finish == "stop" else {
                throw MiMoError.invalidResponse
            }
            history.append(ChatMessage(role: .user, text: prompt))
            history.append(ChatMessage(role: .assistant, text: answer, modelID: model))
            probes.append(["model": model, "reply": answer, "textChunks": chunks,
                           "finishReason": finish!, "done": done])
            print("Live reply verified: \(model), \(chunks) chunks, context retained.")
        }
        let report: [String: Any] = ["date": ISO8601DateFormatter().string(from: .now),
            "models": models.map(\.id), "probes": probes, "keyLogged": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("Verification/live-api.json"), options: .atomic)
    }
}
