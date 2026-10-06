// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import XCTest
@testable import WatchChatCore

final class ChatModelsTests: XCTestCase {
    func testLegacyHistoryDecodesWithoutPreviousReplies() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","role":"assistant",
         "text":"旧的个人记录","date":0,"modelID":"mimo-v2.5","state":"complete"}
        """
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(legacy.utf8))
        XCTAssertEqual(message.text, "旧的个人记录")
        XCTAssertEqual(message.state, .complete)
        XCTAssertNil(message.previousReplies)
    }

    func testPreviousRepliesSurviveRoundTripWithoutEnteringContext() throws {
        let partial = ChatMessage(role: .assistant, text: "上次停止的部分文字",
            modelID: "mimo-v2.6-flash", state: .cancelled, notice: "已停止生成。")
        let latest = ChatMessage(role: .assistant, text: "完整的新回答", modelID: "mimo-v2.5",
            previousReplies: [ReplyAttempt(message: partial)])
        let history = [ChatMessage(role: .user, text: "问题"), latest]
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)
        XCTAssertEqual(decoded.last?.previousReplies?.last?.text, partial.text)
        XCTAssertEqual(decoded.last?.previousReplies?.last?.modelID, "mimo-v2.6-flash")
        XCTAssertEqual(decoded.last?.previousReplies?.last?.state, .cancelled)
        XCTAssertEqual(decoded.last?.previousReplies?.last?.notice, "已停止生成。")
        let context = ChatContext.messages(history: decoded, prompt: "下一问")
        XCTAssertEqual(context.dropFirst().map(\.content), ["问题", "完整的新回答", "下一问"])
        XCTAssertFalse(context.contains { $0.content == partial.text })
    }

    func testRecoveryMarksOnlyGeneratingMessagesAndPreservesTheirContent() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let pendingID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let completed = ChatMessage(role: .assistant, text: "完整回答", date: date,
                                    modelID: "mimo-v2.6-pro", state: .complete)
        let interrupted = ChatMessage(role: .assistant, text: "先前中断", date: date,
                                      state: .interrupted, notice: "已有提示")
        var conversation = Conversation(messages: [
            ChatMessage(role: .user, text: "问题", date: date),
            ChatMessage(id: pendingID, role: .assistant, text: "已收到的部分中文", date: date,
                        modelID: "mimo-v2.6-flash", state: .generating), completed, interrupted
        ], updatedAt: date)
        conversation.recoverInterruptedResponses()

        XCTAssertEqual(conversation.messages[1].state, .interrupted)
        XCTAssertEqual(conversation.messages[1].notice, "上次回复被中断，可以重试。")
        XCTAssertEqual(conversation.messages[1].text, "已收到的部分中文")
        XCTAssertEqual(conversation.messages[1].id, pendingID)
        XCTAssertEqual(conversation.messages[1].date, date)
        XCTAssertEqual(conversation.messages[1].modelID, "mimo-v2.6-flash")
        XCTAssertEqual(conversation.messages[0].state, .complete)
        XCTAssertEqual(conversation.messages[2], completed)
        XCTAssertEqual(conversation.messages[3], interrupted)
        XCTAssertEqual(conversation.updatedAt, date)
        let recovered = conversation
        conversation.recoverInterruptedResponses()
        XCTAssertEqual(conversation, recovered, "Recovery is idempotent")
    }

    func testChatModelFilteringRejectsNonChatModalities() {
        for id in ["mimo-v2.6-flash", "mimo-v2.6-pro", "MIMO-V2.5", "mimo-new-chat"] {
            XCTAssertTrue(MiMoModel.isChatModel(id), id)
        }
        for id in ["other-chat", "", "mimo-tts", "mimo-asr", "mimo-voice", "mimo-embedding",
                   "mimo-rerank", "mimo-audio", "MIMO-V2.5-AUDIO"] {
            XCTAssertFalse(MiMoModel.isChatModel(id), id)
        }
        XCTAssertTrue(MiMoModel.defaults.allSatisfy { MiMoModel.isChatModel($0.id) })
    }

    func testPreferredModelUsesPriorityThenFallsBackToAvailableModel() {
        let choices = ["mimo-v2.6-pro", "mimo-v2-flash", "mimo-v2.5", "mimo-v2.6-flash"]
        XCTAssertEqual(MiMoModel.preferred(in: choices.map(MiMoModel.init)), "mimo-v2.6-flash")
        XCTAssertEqual(MiMoModel.preferred(in: Array(choices.dropLast()).map(MiMoModel.init)), "mimo-v2.5")
        XCTAssertEqual(MiMoModel.preferred(in: ["mimo-v2.6-pro", "mimo-v2-flash"].map(MiMoModel.init)), "mimo-v2-flash")
        XCTAssertEqual(MiMoModel.preferred(in: ["mimo-future", "mimo-v2.6-pro"].map(MiMoModel.init)), "mimo-future")
        XCTAssertNil(MiMoModel.preferred(in: []))
        XCTAssertEqual(MiMoModel.preferred(in: MiMoModel.defaults), "mimo-v2.6-flash")
    }

    func testConversationTitleUsesFirstUserMessageAndTruncatesByCharacter() {
        XCTAssertEqual(Conversation().title, "新对话")
        let text = String(repeating: "🌏", count: 25)
        let conversation = Conversation(messages: [
            ChatMessage(role: .assistant, text: "忽略助手文本"),
            ChatMessage(role: .user, text: text)
        ])
        XCTAssertEqual(conversation.title, String(repeating: "🌏", count: 24) + "…")
        XCTAssertEqual(Conversation(messages: [ChatMessage(role: .user, text: "第一行\n第二行")]).title,
                       "第一行 第二行")
    }
}
