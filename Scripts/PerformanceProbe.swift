// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

@main
struct PerformanceProbe {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = root.appendingPathComponent(".build/PerformanceProbeData")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let history = (0..<100).map { _ in
            Conversation(messages: (0..<12).map { index in
                ChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant,
                    text: String(repeating: "性能验收", count: 70))
            })
        }
        let writer = HistoryWriter(url: directory.appendingPathComponent("async.json"))
        var synchronous: [Double] = [], submissions: [Double] = []
        for _ in 0..<12 {
            let before = Date.now
            try JSONEncoder().encode(history).write(to: directory.appendingPathComponent("sync.json"), options: .atomic)
            synchronous.append(Date.now.timeIntervalSince(before) * 1000)
            let start = Date.now
            writer.submit(history)
            submissions.append(Date.now.timeIntervalSince(start) * 1000)
        }
        try await writer.flush()
        let final = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: directory.appendingPathComponent("async.json")))
        guard final == history else { throw MiMoError.invalidResponse }
        let report: [String: Any] = ["environment": "Apple M5 Mac, optimized Swift build; not watch energy measurement",
            "conversations": history.count, "messages": 1200, "samples": 12,
            "synchronousMainWorkMeanMs": synchronous.reduce(0,+) / 12,
            "backgroundSubmissionMeanMs": submissions.reduce(0,+) / 12,
            "savedHistoryMatches": true, "streamDisplayMinimumIntervalMs": 180, "previousIntervalMs": 80]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("Verification/v1.1-performance.json"), options: .atomic)
        print("Background snapshot benchmark passed; final history matches.")
    }
}
