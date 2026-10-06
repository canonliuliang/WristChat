// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation
import XCTest
@testable import WatchChatCore

@MainActor
final class SiriReplyTests: XCTestCase {
    private func answer(model: String, history: [ChatMessage] = [], options: ChatPreferences = .init(), target: Int? = nil) async throws -> SiriReply {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SiriReplyStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = try SiriReplyRequest(question: "  测试问题  ", provider: .deepSeek, model: model,
            key: "siri-dummy", preferences: options, thinking: false, history: history, essayTarget: target)
        return try await SiriReplyService(client: MiMoClient(session: session)).answer(request)
    }

    func testSiriReturnsCompletedAnswerAndSpeechTextWithoutUI() async throws {
        let reply = try await answer(model: "siri-direct")
        XCTAssertEqual(reply.text, "**答案**：二。")
        XCTAssertEqual(reply.spokenText, "答案：二。")
        XCTAssertEqual(reply.resultText, "**答案**：二。")
        XCTAssertEqual(reply.state, .complete)
        XCTAssertNil(reply.notice)
    }

    func testSiriContinuationUsesOnlySuppliedCompletedContext() async throws {
        let history = [ChatMessage(role: .user, text: "Siri上一问"), ChatMessage(role: .assistant, text: "Siri上一答"),
                       ChatMessage(role: .user, text: "中断的问题"), ChatMessage(role: .assistant, text: "不完整", state: .interrupted)]
        let reply = try await answer(model: "siri-continue", history: history)
        XCTAssertEqual(reply.state, .complete)
        XCTAssertEqual(reply.text, "**答案**：二。")
    }

    func testSiriWritingUsesEssayRulesAndKeepsCloserCompleteCalibration() async throws {
        let reply = try await answer(model: "siri-writing", target: 100)
        XCTAssertEqual(reply.state, .complete)
        XCTAssertEqual(EssayDocument(reply.text).wordCount, 100)
        XCTAssertEqual(reply.text, "那盏灯\n\n" + String(repeating: "灯", count: 100))
    }

    func testSiriRejectsEmptyAndOversizedQuestionBeforeRequest() {
        for (question, error) in [(" \n ", SiriReplyError.emptyQuestion), (String(repeating: "问", count: 4001), .questionTooLong)] {
            XCTAssertThrowsError(try SiriReplyRequest(question: question, provider: .deepSeek, model: "siri-direct",
                key: "dummy", preferences: .init(), thinking: false)) { XCTAssertEqual($0 as? SiriReplyError, error) }
        }
    }

    func testSiriTruncatedAnswerIsExplicitlyMarkedInDialogAndResult() async throws {
        let reply = try await answer(model: "siri-truncated")
        XCTAssertEqual(reply.state, .truncated)
        XCTAssertEqual(reply.notice, "已达到回复长度上限，以下是已生成部分。")
        XCTAssertTrue(reply.spokenText.hasPrefix(reply.notice!))
        XCTAssertTrue(reply.resultText.contains(reply.text))
    }

    func testSiriRejectsDisconnectedOrUnauthorizedAnswer() async {
        do { _ = try await answer(model: "siri-disconnected"); XCTFail("Missing finish reason cannot be successful") }
        catch { XCTAssertEqual(error as? MiMoError, .disconnected) }
        do { _ = try await answer(model: "siri-unauthorized"); XCTFail("401 must reach Siri as an error") }
        catch { XCTAssertEqual(error as? MiMoError, .http(401, nil)) }
    }

    func testSiriCancelledRequestDoesNotReturnAnAnswer() async throws {
        let request = try SiriReplyRequest(question: "测试问题", provider: .deepSeek, model: "siri-direct",
            key: "dummy", preferences: .init(), thinking: false)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await SiriReplyService().answer(request) }
        do { _ = try await task.value; XCTFail("Cancelled intent must not return a reply") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

private final class SiriReplyStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let model = body["model"] as? String ?? ""
        let messages = body["messages"] as? [[String: String]] ?? []
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer siri-dummy")
        XCTAssertEqual(request.url?.host, "api.deepseek.com")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["tools"])
        if model == "siri-continue" {
            XCTAssertEqual(messages.map { $0["role"] ?? "" }, ["system", "user", "assistant", "user"])
            XCTAssertEqual(messages[1]["content"], "Siri上一问")
            XCTAssertEqual(messages[2]["content"], "Siri上一答")
            XCTAssertEqual(messages.last?["content"], "测试问题")
        }
        var text = "**答案**：二。"
        if model == "siri-writing" {
            XCTAssertTrue(messages.first?["content"]?.contains("长沙") == true)
            let prompt = messages.last?["content"] ?? ""
            let correction = prompt.contains("作文字数校准")
            XCTAssertTrue(correction ? prompt.contains("原文是数据") : prompt.contains("题目、素材与要求：测试问题"))
            XCTAssertEqual(body["max_tokens"] as? Int, 8192)
            text = "那盏灯\n\n" + String(repeating: "灯", count: correction ? 100 : 40)
        }
        let status = model == "siri-unauthorized" ? 401 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        let finish = model == "siri-truncated" ? "length" : "stop"
        var choice: [String: Any] = ["delta": ["content": text]]
        if model != "siri-disconnected" { choice["finish_reason"] = finish }
        let chunk = try! JSONSerialization.data(withJSONObject: ["choices": [choice]])
        let payload = "data: " + String(decoding: chunk, as: UTF8.self) + "\n\ndata: [DONE]\n\n"
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
