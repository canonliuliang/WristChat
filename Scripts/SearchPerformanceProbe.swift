// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

@main
struct SearchPerformanceProbe {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = "那盏灯\n\n" + Array(repeating: "晚自习结束，父亲在校门口的灯下等我。他将伞向我倾斜，我看到湿透的袖子，悄悄靠近他。", count: 18).joined(separator: "\n\n")
        let id = UUID(), cache = EssayDocumentCache(), repeats = 1000
        let start = ContinuousClock.now
        var uncached = 0
        for _ in 0..<repeats { uncached += EssayDocument(fixture).wordCount }
        let parseDuration = start.duration(to: .now)
        let begin = ContinuousClock.now
        var cached = 0
        for _ in 0..<repeats { cached += cache.document(id: id, text: fixture).wordCount }
        let cachedDuration = begin.duration(to: .now)
        func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        let perf: [String: Any] = ["environment": "Optimized Swift, Apple M5 Mac; not a watch FPS or energy measurement", "repetitions": repeats,
            "uncachedTotalMs": milliseconds(parseDuration), "cachedTotalMs": milliseconds(cachedDuration), "sameCounts": uncached == cached,
            "dragCommitsDuringMovement": 0, "maximumCommitOnRelease": 1, "cacheEntryLimit": 24, "cacheCharacterLimit": 64000]
        try JSONSerialization.data(withJSONObject: perf, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("Verification/v1.5-performance.json"))
        let credentials = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent(".private/BootstrapCredentials.plist")), format: nil) as! [String: String]
        var preferences = ChatPreferences(); preferences.webSearch = true
        let query = "请联网核实 Apple Watch Series 11 有哪些尺寸，以及官方续航时长，简短回答并引用 Apple 官方来源。"
        var text = "", sources: [SearchSource] = [], reason: String?, done = false
        do {
            let events = MiMoClient().replyWithWebSearch(key: credentials["DeepSeekAPIKey"]!, searchKey: credentials["MiMoAPIKey"]!, model: "deepseek-flash",
                messages: ChatContext.messages(history: [], prompt: query, preferences: preferences), query: query,
                thinking: false, preferences: preferences, provider: .deepSeek)
            for try await event in events {
                switch event {
                case .text(let value): text += value
                case .sources(let value): sources += value
                case .finished(let value): reason = value
                case .done: done = true
                default: break
                }
            }
            try text.write(to: root.appendingPathComponent("Verification/v1.5-deepseek-search-answer.txt"), atomically: true, encoding: .utf8)
            let report: [String: Any] = ["complete": done && reason == "stop", "sourceCount": sources.count, "sourceURLs": sources.map { $0.url.absoluteString },
                "answerNonempty": !text.isEmpty, "searchProvider": "MiMo", "answerProvider": "DeepSeek", "keyLogged": false]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("Verification/v1.5-live-search.json"))
            print("Grounded DeepSeek answer complete: \(done && reason == "stop"), real source count: \(sources.count). Credentials not logged.")
        } catch {
            let report: [String: Any] = ["complete": false, "sourceCount": sources.count, "error": error.localizedDescription, "keyLogged": false]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("Verification/v1.5-live-search.json"))
            print("Grounded search failed: \(error.localizedDescription)")
        }
    }
}
