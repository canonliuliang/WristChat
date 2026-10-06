// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation
import XCTest
@testable import WatchChatCore

@MainActor
final class HistoryWriterTests: XCTestCase {
    func testIdenticalSnapshotsDoNotRewriteSavedHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let writer = HistoryWriter(url: url)
        let history = [Conversation(messages: [ChatMessage(role: .assistant, text: String(repeating: "正文", count: 400))])]
        writer.submit(history)
        try await writer.flush()
        let marker = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: url.path)
        for _ in 0..<20 { writer.submit(history); try await writer.flush() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, marker, "Unchanged snapshots must not rewrite the file")
        XCTAssertEqual(try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: url)), history)
    }

    func testChangedTextAndCompletionStatePersistAfterDuplicateSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let writer = HistoryWriter(url: url)
        var conversation = Conversation(messages: [ChatMessage(role: .assistant, text: "第一段", state: .generating)])
        writer.submit([conversation]); try await writer.flush()
        writer.submit([conversation]); try await writer.flush()
        conversation.messages[0].text += "，最后一段。"
        writer.submit([conversation]); try await writer.flush()
        XCTAssertEqual(try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: url)), [conversation])
        // A completion with identical text must still be persisted.
        conversation.messages[0].state = .complete
        writer.submit([conversation]); try await writer.flush()
        XCTAssertEqual(try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: url)), [conversation])
    }

    func testCoalescedSnapshotsPersistLatestHistoryThenDeletionWithoutStaleWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let writer = HistoryWriter(url: url)
        var conversation = Conversation(messages: [ChatMessage(role: .user, text: "问题"), ChatMessage(role: .assistant, text: "")])
        for index in 0..<100 {
            conversation.messages[1].text = String(repeating: "长回答", count: index * 10)
            writer.submit([conversation])
        }
        try await writer.flush()
        let saved = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: url))
        XCTAssertEqual(saved, [conversation], "Last snapshot must win, including the final streamed characters")
        writer.submit([])
        try await writer.flush()
        XCTAssertEqual(try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: url)), [])
    }

    func testWriteFailureIsReportedAndARepairedDirectoryCanRecover() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let writer = HistoryWriter(url: url)
        let recovered = Conversation(messages: [ChatMessage(role: .user, text: "保留的内容")])
        writer.submit([recovered])
        do { try await writer.flush(); XCTFail("Missing directory must report failure") } catch {}
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writer.submit([recovered])
        try await writer.flush()
        XCTAssertEqual(try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: url)), [recovered])
    }

    func testFailedChangeThenRetryPreviousSnapshotRecreatesHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let writer = HistoryWriter(url: url)
        let original = [Conversation(messages: [ChatMessage(role: .assistant, text: "已保存")])]
        writer.submit(original); try await writer.flush()
        try FileManager.default.removeItem(at: directory)
        writer.submit([])
        do { try await writer.flush(); XCTFail("The failed changed snapshot must be reported") } catch {}
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writer.submit(original); try await writer.flush()
        XCTAssertEqual(try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: url)), original,
                       "An old successful snapshot must not be mistaken for a successful retry")
    }
}
