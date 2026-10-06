// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

public enum SiriReplyError: LocalizedError, Equatable {
    case emptyQuestion, questionTooLong, noPreviousConversation, busy, unsupportedSearch
    public var errorDescription: String? {
        switch self {
        case .emptyQuestion: "请说出问题或作文题目。"
        case .questionTooLong: "这次问题太长，请控制在4000字以内。"
        case .noPreviousConversation: "还没有上一段 Siri 对话。直接说“腕聊帮我”问一个问题即可。"
        case .busy: "Siri 中的上一条问题还在回答，请稍后再问。"
        case .unsupportedSearch: "当前提供商还不能联网搜索。请在腕聊设置中选择 MiMo 或 DeepSeek。"
        }
    }
}

public struct SiriReplyRequest: Sendable {
    public let question: String
    public let provider: AIProvider
    public let model: String
    public let key: String
    public let searchKey: String
    public var preferences: ChatPreferences
    public let thinking: Bool
    public let history: [ChatMessage]
    public let essayTarget: Int?

    public init(question: String, provider: AIProvider, model: String, key: String,
                searchKey: String = "", preferences: ChatPreferences, thinking: Bool,
                history: [ChatMessage] = [], essayTarget: Int? = nil) throws {
        let trimmed = try SiriQuestionText.validate(question)
        self.question = trimmed; self.provider = provider; self.model = model
        self.key = key; self.searchKey = searchKey; self.preferences = preferences
        self.thinking = thinking && provider.supportsThinking; self.history = history
        self.essayTarget = essayTarget
        if essayTarget != nil { self.preferences.essayMode = true }
        self.preferences.webSearch = preferences.webSearch && (provider.supportsSearch || provider.apiProtocol == .deepSeek)
    }

    public var prompt: String {
        guard let essayTarget else { return question }
        return "作文生成任务。题目、素材与要求：\(question)\n正文约\(essayTarget)个汉字，标题与标点不计。输出标题和完整正文，开头明确点题并引出下文，最后2–3段逐层写感悟、主旨与立意。"
    }
}

public struct SiriReply: Sendable {
    public let text: String
    public let sources: [SearchSource]
    public let state: MessageState
    public let notice: String?

    public var spokenText: String {
        [notice, SpokenReply.text(from: text)].compactMap { $0 }.joined(separator: "\n")
    }
    public var resultText: String {
        var result = [notice, text].compactMap { $0 }.joined(separator: "\n\n")
        if !sources.isEmpty {
            result += "\n\n来源：\n" + sources.map { "\($0.title)：\($0.url.absoluteString)" }.joined(separator: "\n")
        }
        return result
    }
}

/// Independent of the foreground reply task, draft and workspace.
public struct SiriReplyService: Sendable {
    private let client: MiMoClient
    public init(client: MiMoClient = .init()) { self.client = client }

    public func answer(_ request: SiriReplyRequest,
                       progress: @Sendable (Int) -> Void = { _ in }) async throws -> SiriReply {
        try Task.checkCancellation()
        let messages = ChatContext.messages(history: request.history, prompt: request.prompt, preferences: request.preferences)
        let stream: AsyncThrowingStream<StreamEvent, Error>
        if request.preferences.webSearch && request.provider.apiProtocol == .deepSeek {
            stream = client.replyWithWebSearch(key: request.key, searchKey: request.searchKey, model: request.model,
                messages: messages, query: request.question, thinking: request.thinking,
                preferences: request.preferences, provider: request.provider)
        } else {
            stream = try client.reply(key: request.key, model: request.model, messages: messages,
                thinking: request.thinking, preferences: request.preferences, provider: request.provider)
        }
        var reply = try await collect(stream, progress: progress)
        // Retain the first completed draft if calibration fails or is worse.
        if reply.state == .complete, let target = request.essayTarget,
           EssaySizing.needsAdjustment(actual: EssayDocument(reply.text).wordCount, target: target) {
            var options = request.preferences; options.webSearch = false
            do {
                let correction = try client.reply(key: request.key, model: request.model,
                    messages: ChatContext.messages(history: [], prompt: EssaySizing.prompt(text: reply.text, target: target), preferences: options),
                    thinking: request.thinking, preferences: options, provider: request.provider)
                let adjusted = try await collect(correction, progress: progress)
                if adjusted.state == .complete, EssaySizing.preferRevision(original: EssayDocument(reply.text).wordCount,
                    revised: EssayDocument(adjusted.text).wordCount, target: target) {
                    reply = SiriReply(text: adjusted.text, sources: reply.sources, state: .complete, notice: reply.notice)
                }
            } catch { if Task.isCancelled { throw CancellationError() } }
        }
        try Task.checkCancellation()
        return reply
    }

    private func collect(_ stream: AsyncThrowingStream<StreamEvent, Error>,
                         progress: @Sendable (Int) -> Void) async throws -> SiriReply {
        var text = "", sources: [SearchSource] = [], reason: String?, done = false, searchFailed = false
        var eventCount = 0
        for try await event in stream {
            try Task.checkCancellation()
            eventCount += 1; progress(eventCount)
            switch event {
            case .text(let delta):
                text += delta
                guard text.count <= 100_000 else { throw MiMoError.invalidResponse }
            case .sources(let values):
                var seen = Set(sources.map(\.id))
                sources += values.filter { seen.insert($0.id).inserted }
            case .searchFailed: searchFailed = true
            case .finished(let value): reason = value
            case .done: done = true
            case .thinking: break
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MiMoError.emptyResponse }
        guard done, let reason else { throw MiMoError.disconnected }
        let state: MessageState = reason == "stop" ? .complete : (reason == "length" ? .truncated : .interrupted)
        let notices = [searchFailed ? "本次联网搜索失败，回答未核实实时信息。" : nil,
                       reason == "length" ? "已达到回复长度上限，以下是已生成部分。" : nil,
                       state == .interrupted ? "回复提前结束，以下是已生成部分。" : nil].compactMap { $0 }
        return SiriReply(text: text, sources: sources, state: state, notice: notices.isEmpty ? nil : notices.joined(separator: "\n"))
    }
}
