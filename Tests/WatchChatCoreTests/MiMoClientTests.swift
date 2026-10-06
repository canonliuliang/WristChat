// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation
import XCTest
@testable import WatchChatCore

@MainActor
final class MiMoClientTests: XCTestCase {
    func testSearchEnabledSendsOfficialToolAndShortBudget() async throws {
        let session = makeSession(protocolClass: SearchRequestProtocol.self)
        defer { session.invalidateAndCancel() }
        var preferences = ChatPreferences(); preferences.webSearch = true
        let stream = try MiMoClient(session: session).reply(key: "unit-test-key", model: "mimo-v2.6-flash",
            messages: [APIMessage(role: "user", content: "测试")], thinking: false, preferences: preferences)
        var events: [StreamEvent] = []
        for try await event in stream { events.append(event) }
        XCTAssertEqual(events, [.text("完整回答"), .finished("stop"), .done])
    }

    func testSearchDisabledLongThinkingRequestOmitsToolsAndHonorsWiFiOnly() async throws {
        let session = makeSession(protocolClass: OfflineLongRequestProtocol.self)
        defer { session.invalidateAndCancel() }
        var preferences = ChatPreferences(); preferences.answerLength = .long; preferences.allowsCellular = false
        let stream = try MiMoClient(session: session).reply(key: "unit-test-key", model: "mimo-v2.6-flash",
            messages: [APIMessage(role: "user", content: "测试")], thinking: true, preferences: preferences)
        var events: [StreamEvent] = []
        for try await event in stream { events.append(event) }
        XCTAssertEqual(events.last, .done)
    }

    func testSearchRejectionDoesNotSilentlyFallbackToUnsearchedAnswer() async throws {
        let session = makeSession(protocolClass: SearchDeniedProtocol.self)
        defer { session.invalidateAndCancel() }
        var preferences = ChatPreferences(); preferences.webSearch = true
        let stream = try MiMoClient(session: session).reply(key: "unit-test-key", model: "mimo-v2.6-flash",
            messages: [APIMessage(role: "user", content: "测试")], thinking: false, preferences: preferences)
        do { for try await _ in stream {}; XCTFail("Search rejection must be visible") }
        catch { XCTAssertEqual(error as? MiMoError, .searchUnavailable) }
    }

    func testModelsRequestFiltersDeduplicatesAndSortsAuthenticatedResult() async throws {
        let session = makeSession(protocolClass: ModelsSuccessProtocol.self)
        defer { session.invalidateAndCancel() }
        let models = try await MiMoClient(session: session).models(key: "unit-test-key")
        XCTAssertEqual(models.map(\.id), ["mimo-v2.5", "mimo-v2.6-flash", "mimo-v2.6-pro"])
        XCTAssertEqual(MiMoModel.preferred(in: models), "mimo-v2.6-flash")
    }

    func testModelsRequestReportsUnauthorizedStatus() async {
        let session = makeSession(protocolClass: UnauthorizedProtocol.self)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await MiMoClient(session: session).models(key: "unit-test-key")
            XCTFail("Expected unauthorized response to fail")
        } catch {
            XCTAssertEqual(error as? MiMoError, .http(401, nil))
            XCTAssertEqual(error.localizedDescription, "密钥无效或无权使用此模型，请检查设置。")
        }
    }

    func testModelsRequestRejectsListWithoutChatModels() async {
        let session = makeSession(protocolClass: NoChatModelsProtocol.self)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await MiMoClient(session: session).models(key: "unit-test-key")
            XCTFail("A model picker cannot use an empty chat-model list")
        } catch {
            XCTAssertEqual(error as? MiMoError, .invalidResponse)
        }
    }

    func testMissingKeyFailsBeforeRequestForModelsAndReply() async {
        let session = makeSession(protocolClass: MustNotSendProtocol.self)
        defer { session.invalidateAndCancel() }
        let client = MiMoClient(session: session)
        do {
            _ = try await client.models(key: " \n\t ")
            XCTFail("Whitespace key must fail")
        } catch {
            XCTAssertEqual(error as? MiMoError, .missingKey)
        }
        XCTAssertThrowsError(try client.reply(key: "", model: "mimo-v2.6-flash",
                                             messages: [APIMessage(role: "user", content: "测试")],
                                             thinking: false)) { error in
            XCTAssertEqual(error as? MiMoError, .missingKey)
        }
    }

    func testReplyReplaysFragmentedChineseCRLFStreamThroughDone() async throws {
        let session = makeSession(protocolClass: CompleteReplyProtocol.self)
        defer { session.invalidateAndCancel() }
        let stream = try MiMoClient(session: session).reply(
            key: "unit-test-key", model: "mimo-v2.6-flash",
            messages: [APIMessage(role: "user", content: "你好")], thinking: false)
        var events: [StreamEvent] = []
        for try await event in stream { events.append(event) }
        XCTAssertEqual(events, [.text("你好，"), .text("手表 🌏"), .finished("stop"), .done])
    }

    func testReplyPreservesFinalTextAtEOFThenReportsDisconnected() async throws {
        let session = makeSession(protocolClass: InterruptedReplyProtocol.self)
        defer { session.invalidateAndCancel() }
        let stream = try MiMoClient(session: session).reply(
            key: "unit-test-key", model: "mimo-v2.6-flash",
            messages: [APIMessage(role: "user", content: "你好")], thinking: false)
        var events: [StreamEvent] = []
        do {
            for try await event in stream { events.append(event) }
            XCTFail("Transport EOF without [DONE] must not appear complete")
        } catch {
            XCTAssertEqual(error as? MiMoError, .disconnected)
        }
        XCTAssertEqual(events, [.text("已经收到"), .text("尾段 🌏")],
                       "The final unterminated UTF-8 line must be decoded before reporting interruption")
    }

    func testReplyAcceptsDoneAtEOFWithoutTrailingNewline() async throws {
        let session = makeSession(protocolClass: DoneAtEOFReplyProtocol.self)
        defer { session.invalidateAndCancel() }
        let stream = try MiMoClient(session: session).reply(
            key: "unit-test-key", model: "mimo-v2.6-flash",
            messages: [APIMessage(role: "user", content: "你好")], thinking: false)
        var events: [StreamEvent] = []
        for try await event in stream { events.append(event) }
        XCTAssertEqual(events, [.text("完整回答"), .finished("stop"), .done])
    }

    private func makeSession(protocolClass: AnyClass) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }
}

private class ModelStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    class var status: Int { 200 }
    class var body: String { "{}" }

    override func startLoading() {
        guard request.url?.absoluteString == "https://api.xiaomimimo.com/v1/models",
              request.value(forHTTPHeaderField: "api-key") == "unit-test-key",
              request.value(forHTTPHeaderField: "Content-Type") == "application/json" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ModelsSuccessProtocol: ModelStubProtocol, @unchecked Sendable {
    override class var body: String {
        #"{"data":[{"id":"mimo-v2.6-pro"},{"id":"mimo-audio"},{"id":"mimo-v2.6-flash"},{"id":"other-chat"},{"id":"mimo-v2.5"},{"id":"mimo-v2.6-flash"}]}"#
    }
}

private final class UnauthorizedProtocol: ModelStubProtocol, @unchecked Sendable {
    override class var status: Int { 401 }
    override class var body: String { #"{"error":{"message":"invalid test key"}}"# }
}

private final class NoChatModelsProtocol: ModelStubProtocol, @unchecked Sendable {
    override class var body: String { #"{"data":[{"id":"mimo-tts"},{"id":"other-chat"}]}"# }
}

private final class MustNotSendProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("A missing key must be rejected before any request starts")
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

private class ReplyStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    class var payload: String { "" }
    class var status: Int { 200 }
    func validateBody() {}

    override func startLoading() {
        guard request.url?.absoluteString == "https://api.xiaomimimo.com/v1/chat/completions",
              request.httpMethod == "POST",
              request.value(forHTTPHeaderField: "api-key") == "unit-test-key",
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              request.value(forHTTPHeaderField: "Accept") == "text/event-stream" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        validateBody()
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Splits both CRLF and multibyte Chinese/emoji characters across transport callbacks.
        for byte in Self.payload.utf8 {
            client?.urlProtocol(self, didLoad: Data([byte]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CompleteReplyProtocol: ReplyStubProtocol, @unchecked Sendable {
    override class var payload: String {
        [
            ": heartbeat", "",
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"你好，"}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"手表 🌏"}}]}"#, "",
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#, "",
            #"data: {"usage":{"completion_tokens":5}}"#, "",
            "data: [DONE]", "",
            "data: invalid trailing event that must be ignored", "", ""
        ].joined(separator: "\r\n")
    }
}

private final class InterruptedReplyProtocol: ReplyStubProtocol, @unchecked Sendable {
    override class var payload: String {
        [
            #"data: {"choices":[{"delta":{"content":"已经收到"}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"尾段 🌏"}}]}"#
        ].joined(separator: "\r\n")
    }
}

private final class DoneAtEOFReplyProtocol: ReplyStubProtocol, @unchecked Sendable {
    override class var payload: String {
        [
            #"data: {"choices":[{"delta":{"content":"完整回答"},"finish_reason":"stop"}]}"#, "",
            "data: [DONE]"
        ].joined(separator: "\r\n")
    }
}

private class PreferenceRequestProtocol: ReplyStubProtocol, @unchecked Sendable {
    override class var payload: String {
        #"data: {"choices":[{"delta":{"content":"完整回答"},"finish_reason":"stop"}]}"# + "\n\ndata: [DONE]\n\n"
    }
    func body() -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

private final class SearchRequestProtocol: PreferenceRequestProtocol, @unchecked Sendable {
    override func validateBody() {
        let value = body()
        XCTAssertEqual(value["max_completion_tokens"] as? Int, 2048)
        XCTAssertEqual((value["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertEqual(value["tool_choice"] as? String, "auto")
        let tools = value["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 1)
        XCTAssertEqual(tools?.first?["type"] as? String, "web_search")
        XCTAssertEqual(tools?.first?["force_search"] as? Bool, true)
        XCTAssertEqual(tools?.first?["max_keyword"] as? Int, 1)
        XCTAssertTrue(request.allowsCellularAccess)
    }
}

private final class OfflineLongRequestProtocol: PreferenceRequestProtocol, @unchecked Sendable {
    override func validateBody() {
        let value = body()
        XCTAssertNil(value["tools"])
        XCTAssertNil(value["tool_choice"])
        XCTAssertEqual(value["max_completion_tokens"] as? Int, 16384)
        XCTAssertEqual((value["thinking"] as? [String: String])?["type"], "enabled")
        XCTAssertFalse(request.allowsCellularAccess)
        XCTAssertFalse(request.allowsExpensiveNetworkAccess)
    }
}

private final class SearchDeniedProtocol: PreferenceRequestProtocol, @unchecked Sendable {
    override class var status: Int { 400 }
}
