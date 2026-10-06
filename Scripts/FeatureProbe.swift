// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

@main
struct FeatureProbe {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let data = try Data(contentsOf: root.appendingPathComponent(".private/BootstrapCredentials.plist"))
        let config = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
        let client = MiMoClient()
        var reports: [[String: Any]] = []
        for search in [false, true] {
            var preferences = ChatPreferences()
            preferences.webSearch = search
            preferences.answerLength = search ? .short : .long
            let prompt = search ? "请查询小米 MiMo 官方文档，说明联网搜索是否支持 mimo-v2.6-flash。简短回答。" : "用Markdown表格比较短回答和长回答，列为模式、适合问题，两行即可，然后写一句说明。"
            var answer = "", sources: [SearchSource] = []
            var finish = "", done = false, searchFailed = false
            let started = Date.now
            do {
                let stream = try client.reply(key: config["MiMoAPIKey"]!, model: "mimo-v2.6-flash",
                    messages: ChatContext.messages(history: [], prompt: prompt, preferences: preferences),
                    thinking: false, preferences: preferences)
                for try await event in stream {
                    switch event {
                    case .text(let text): answer += text
                    case .sources(let result): sources += result
                    case .searchFailed: searchFailed = true
                    case .finished(let reason): finish = reason
                    case .done: done = true
                    case .thinking: break
                    }
                }
                let hasTable = ReplyDocument.parse(answer).contains { if case .table = $0 { true } else { false } }
                let passed = done && finish == "stop" && !answer.isEmpty && (search ? !sources.isEmpty && !searchFailed : hasTable)
                reports.append(["webSearch": search, "passed": passed, "hasTable": hasTable,
                    "sourceCount": sources.count, "sources": sources.map(\.id), "searchFailed": searchFailed,
                    "answerCharacters": answer.count, "finish": finish, "seconds": Date.now.timeIntervalSince(started)])
                print("Feature probe: search=\(search), passed=\(passed), sources=\(sources.count), table=\(hasTable)")
            } catch {
                reports.append(["webSearch": search, "passed": false, "error": error.localizedDescription])
                print("Feature probe: search=\(search), unavailable: \(error.localizedDescription)")
            }
        }
        let output: [String: Any] = ["date": ISO8601DateFormatter().string(from: .now), "probes": reports, "keyLogged": false]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("Verification/v1.1-live-api.json"), options: .atomic)
    }
}
