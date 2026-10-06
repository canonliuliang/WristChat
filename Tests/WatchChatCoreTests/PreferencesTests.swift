// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import XCTest
@testable import WatchChatCore

final class PreferencesTests: XCTestCase {
    func testSilentOverridesHapticsAndShortLongBudgetsReserveThinkingTokens() {
        var options = ChatPreferences()
        for (silent, haptics, expected) in [(false, true, true), (false, false, false), (true, true, false), (true, false, false)] {
            options.silent = silent; options.haptics = haptics
            XCTAssertEqual(options.shouldNotify, expected)
        }
        for (length, plain, thinking) in [(AnswerLength.short, 2048, 8192), (.long, 8192, 16384)] {
            options.answerLength = length
            XCTAssertEqual(options.completionBudget(thinking: false), plain)
            XCTAssertEqual(options.completionBudget(thinking: true), thinking)
        }
    }

    func testContextDepthKeepsOnlyRecentWholePairsAndCanDisableContext() {
        let history = (1...10).flatMap { [ChatMessage(role: .user, text: "Q\($0)"), ChatMessage(role: .assistant, text: "A\($0)")] }
        for (depth, first, count) in [(ContextDepth.none, "当前", 2), (.recent, "Q8", 8), (.extended, "Q3", 18)] {
            var options = ChatPreferences(); options.contextDepth = depth
            let messages = ChatContext.messages(history: history, prompt: "当前", preferences: options)
            XCTAssertEqual(messages.count, count)
            XCTAssertEqual(messages[1].content, first)
            XCTAssertEqual(messages.last, APIMessage(role: "user", content: "当前"))
        }
    }

    func testInstructionsReflectLengthLanguageSearchAndBoundedPersonalPreference() throws {
        var options = ChatPreferences()
        options.answerLength = .long; options.language = .english; options.webSearch = true
        options.customInstruction = String(repeating: "偏", count: 600) + "越界"
        let instruction = try XCTUnwrap(ChatContext.messages(history: [], prompt: "测试", preferences: options).first?.content)
        XCTAssertTrue(instruction.contains("详细解释"))
        XCTAssertTrue(instruction.contains("默认用英语"))
        XCTAssertTrue(instruction.contains("已提供联网搜索工具"))
        XCTAssertTrue(instruction.contains("Markdown 表格"))
        XCTAssertFalse(instruction.contains("没有联网搜索工具"))
        XCTAssertFalse(instruction.contains("越界"))
        options.webSearch = false; options.answerLength = .short; options.language = .automatic
        let offline = ChatContext.messages(history: [], prompt: "test", preferences: options)[0].content
        XCTAssertTrue(offline.contains("150字以内"))
        XCTAssertTrue(offline.contains("使用用户提问的语言"))
        XCTAssertTrue(offline.contains("没有联网搜索工具"))
    }

    func testHistoryTimeUsesWholeMinutesHoursDaysAndNoSeconds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cases: [(Double, String)] = [(-10, "刚刚"), (0, "刚刚"), (59.999, "刚刚"), (60, "1分钟前"),
            (119.9, "1分钟前"), (120, "2分钟前"), (3599.9, "59分钟前"), (3600, "1小时前"),
            (86399.9, "23小时前"), (86400, "1天前"), (604799, "6天前")]
        for (seconds, expected) in cases {
            let result = HistoryTime.label(for: now.addingTimeInterval(-seconds), now: now)
            XCTAssertEqual(result, expected, "Boundary \(seconds)")
            XCTAssertFalse(result.contains("秒"))
        }
        XCTAssertFalse(HistoryTime.label(for: now.addingTimeInterval(-604800), now: now).contains("秒"))
    }
}
