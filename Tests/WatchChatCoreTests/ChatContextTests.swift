// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import XCTest
@testable import WatchChatCore

final class ChatContextTests: XCTestCase {
    func testCancelledInterruptedAndTruncatedExchangesAreExcluded() {
        for state in [MessageState.cancelled, .interrupted, .truncated, .failed, .generating] {
            let history = [
                message(.user, "已完成问题"), message(.assistant, "已完成回答"),
                message(.user, "不能保留的问题"), message(.assistant, "部分回答", state: state),
                message(.user, "后来问题"), message(.assistant, "后来回答")
            ]
            XCTAssertEqual(withoutSystem(ChatContext.messages(history: history, prompt: "新问题")), [
                APIMessage(role: "user", content: "已完成问题"),
                APIMessage(role: "assistant", content: "已完成回答"),
                APIMessage(role: "user", content: "后来问题"),
                APIMessage(role: "assistant", content: "后来回答"),
                APIMessage(role: "user", content: "新问题")
            ], "Must omit the entire \(state.rawValue) exchange")
        }
    }

    func testDanglingUsersAndOrphanAssistantsAreExcluded() {
        let history = [
            message(.assistant, "没有对应问题"),
            message(.user, "被替代的问题"), message(.user, "有效问题"), message(.assistant, "有效回答"),
            message(.user, "空回答的问题"), message(.assistant, ""),
            message(.user, "末尾未回答的问题")
        ]
        XCTAssertEqual(withoutSystem(ChatContext.messages(history: history, prompt: "当前问题")), [
            APIMessage(role: "user", content: "有效问题"),
            APIMessage(role: "assistant", content: "有效回答"),
            APIMessage(role: "user", content: "当前问题")
        ])
    }

    func testBudgetBoundaryKeepsOnlyWholeRecentExchanges() {
        let history = [
            message(.user, "OLDQ"), message(.assistant, "OLDA"),
            message(.user, "newq"), message(.assistant, "newa")
        ]
        let current = APIMessage(role: "user", content: "hi")
        let recent = [APIMessage(role: "user", content: "newq"), APIMessage(role: "assistant", content: "newa")]
        let older = [APIMessage(role: "user", content: "OLDQ"), APIMessage(role: "assistant", content: "OLDA")]
        for (budget, expected) in [(9, [current]), (10, recent + [current]), (17, recent + [current]),
                                   (18, older + recent + [current]), (19, older + recent + [current])] {
            XCTAssertEqual(withoutSystem(ChatContext.messages(history: history, prompt: "hi", characterBudget: budget)),
                           expected, "Budget \(budget) must trim complete pairs and preserve chronological order")
        }
    }

    func testOverBudgetPromptIsRetainedWithoutHistoricalPairs() {
        let history = [message(.user, "旧问题"), message(.assistant, "旧回答")]
        let result = ChatContext.messages(history: history, prompt: "这个当前问题超过了预算", characterBudget: 2)
        XCTAssertEqual(result.map(\.role), ["system", "user"])
        XCTAssertEqual(result.last?.content, "这个当前问题超过了预算")
    }

    func testSwitchingModelRetainsCompletedHistoricalContent() {
        let history = [
            message(.user, "记住我的偏好"),
            message(.assistant, "我会简短回答", model: "mimo-v2.6-flash"),
            message(.user, "再分析一下"),
            message(.assistant, "这里是分析", model: "mimo-v2.6-pro")
        ]
        XCTAssertEqual(withoutSystem(ChatContext.messages(history: history, prompt: "换模型继续")), [
            APIMessage(role: "user", content: "记住我的偏好"),
            APIMessage(role: "assistant", content: "我会简短回答"),
            APIMessage(role: "user", content: "再分析一下"),
            APIMessage(role: "assistant", content: "这里是分析"),
            APIMessage(role: "user", content: "换模型继续")
        ])
    }

    func testSystemInstructionUsesShanghaiCalendarDate() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-04T17:30:00Z"))
        let result = ChatContext.messages(history: [], prompt: "今天？", date: date)
        XCTAssertEqual(result.map(\.role), ["system", "user"])
        XCTAssertTrue(try XCTUnwrap(result.first?.content).contains("今天是 2026-10-05。"))
        XCTAssertTrue(try XCTUnwrap(result.first?.content).contains("没有联网搜索工具"))
    }

    private func message(_ role: MessageRole, _ text: String, state: MessageState = .complete,
                         model: String? = nil) -> ChatMessage {
        ChatMessage(role: role, text: text, date: Date(timeIntervalSince1970: 0), modelID: model, state: state)
    }

    private func withoutSystem(_ messages: [APIMessage]) -> [APIMessage] {
        Array(messages.dropFirst())
    }
}
