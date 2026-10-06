// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import XCTest
@testable import WatchChatCore

final class StreamDecoderTests: XCTestCase {
    func testSearchSourcesRejectUnsafeURLsAndPreserveWireOrderWithSearchFailure() throws {
        var decoder = StreamDecoder()
        let source = try XCTUnwrap(SearchSource(url: "https://example.com/page", title: "文档", site: "示例站"))
        let payload = #"{"choices":[{"delta":{"annotations":[{"url":"https://example.com/page","title":"文档","site_name":"示例站"},{"url":"javascript:alert(1)"},{"url":"file:///private/test"}],"error_message":"plugin failed","content":"回答"}}]}"#
        XCTAssertEqual(try decode(payload, with: &decoder), [.sources([source]), .searchFailed, .text("回答")])
        let message = ChatMessage(role: .assistant, text: "回答", sources: [source])
        let restored = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(restored.sources, [source])
        XCTAssertEqual(ReplyAttempt(message: restored).sources, [source])
    }

    func testChineseTextAcrossEventsPreservesCharacters() throws {
        var decoder = StreamDecoder()
        var events: [StreamEvent] = []
        for line in [
            #"data: {"choices":[{"delta":{"content":"你好，"}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"世界 🌏\n今天聊什么？"}}]}"#, ""
        ] {
            events += try decoder.append(line: line)
        }
        XCTAssertEqual(events, [.text("你好，"), .text("世界 🌏\n今天聊什么？")])
        XCTAssertEqual(try decoder.flush(), [])
    }

    func testMultilinePayloadCommentsAndCRDecodeAtBlankLine() throws {
        var decoder = StreamDecoder()
        for line in [
            ": heartbeat\r", "id: 42\r", "event: message\r",
            "data: {\r", #"data: "choices": [{"delta": {"content": "多行中文"}}]"# + "\r",
            ": ignored between data lines\r", "data: }\r"
        ] {
            XCTAssertEqual(try decoder.append(line: line), [], "Must wait for the event delimiter")
        }
        XCTAssertEqual(try decoder.append(line: "\r"), [.text("多行中文")])
        XCTAssertEqual(try decoder.flush(), [])
    }

    func testRoleOnlyAndUsageOnlyChunksProduceNoReplyText() throws {
        var decoder = StreamDecoder()
        for payload in [
            #"{"choices":[{"delta":{"role":"assistant"}}]}"#,
            #"{"usage":{"prompt_tokens":12,"completion_tokens":0}}"#,
            #"{"choices":[],"usage":{"completion_tokens":3}}"#
        ] {
            XCTAssertEqual(try decode(payload, with: &decoder), [])
        }
        XCTAssertEqual(try decode(#"{"choices":[{"delta":{"content":"正文"}}]}"#, with: &decoder),
                       [.text("正文")])
    }

    func testThinkingTextAndFinishEventsKeepWireOrder() throws {
        var decoder = StreamDecoder()
        let payload = #"{"choices":[{"delta":{"reasoning_content":"private reasoning","content":"回答"},"finish_reason":"length"}]}"#
        XCTAssertEqual(try decode(payload, with: &decoder), [.thinking, .text("回答"), .finished("length")])
        XCTAssertEqual(try decode(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#, with: &decoder),
                       [.finished("stop")])
    }

    func testDoneSentinelAcceptsSurroundingWhitespace() throws {
        var decoder = StreamDecoder()
        XCTAssertEqual(try decode("  [DONE]  ", with: &decoder), [.done])
        XCTAssertEqual(try decoder.flush(), [])
    }

    func testErrorEventAndErrorObjectThrowServerErrorAndReset() throws {
        for (event, payload) in [
            ("event: error", #"{"message":"provider unavailable"}"#),
            ("event: message", #"{"error":{"message":"quota exceeded"}}"#)
        ] {
            var decoder = StreamDecoder()
            XCTAssertEqual(try decoder.append(line: event), [])
            XCTAssertThrowsError(try decode(payload, with: &decoder)) { error in
                XCTAssertEqual(error as? MiMoError, .server("stream_error"))
            }
            XCTAssertEqual(try decode(#"{"choices":[{"delta":{"content":"重试成功"}}]}"#, with: &decoder),
                           [.text("重试成功")], "An error must not contaminate the next event")
        }
    }

    func testInvalidPayloadsThrowInvalidResponseAndReset() throws {
        for payload in ["not json", "[]", #"{"unexpected":true}"#, #"{"choices":"wrong type"}"#] {
            var decoder = StreamDecoder()
            XCTAssertThrowsError(try decode(payload, with: &decoder)) { error in
                XCTAssertEqual(error as? MiMoError, .invalidResponse, payload)
            }
            XCTAssertEqual(try decode(#"{"choices":[{"delta":{"content":"有效"}}]}"#, with: &decoder),
                           [.text("有效")])
        }
    }

    func testFlushAtEndOfFileEmitsPendingEventOnlyOnce() throws {
        var decoder = StreamDecoder()
        XCTAssertEqual(try decoder.append(line: #"data:{"choices":[{"delta":{"content":"尾部"}}]}"#), [])
        XCTAssertEqual(try decoder.flush(), [.text("尾部")])
        XCTAssertEqual(try decoder.flush(), [])
        XCTAssertEqual(try decoder.append(line: ""), [])
    }

    func testEmptyEventsAndUnknownFieldsProduceNoEvents() throws {
        var decoder = StreamDecoder()
        for line in ["", ": comment", "retry: 5000", "id: 1", "event: message", "data:", ""] {
            XCTAssertEqual(try decoder.append(line: line), [])
        }
    }

    private func decode(_ payload: String, with decoder: inout StreamDecoder) throws -> [StreamEvent] {
        XCTAssertEqual(try decoder.append(line: "data: " + payload), [])
        return try decoder.append(line: "")
    }
}
