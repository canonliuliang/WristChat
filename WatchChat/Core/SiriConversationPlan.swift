// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

public enum SiriResponseStyle: String, Codable, CaseIterable, Sendable {
    case quick, balanced, followApp
    public var title: String {
        switch self { case .quick: "简洁快答"; case .balanced: "适度解释"; case .followApp: "跟随聊天设置" }
    }
}

public struct SiriPreferences: Codable, Equatable, Sendable {
    public var responseStyle: SiriResponseStyle = .quick
    public var automaticallyContinues = true
    public init() {}
    private enum CodingKeys: String, CodingKey { case responseStyle, automaticallyContinues }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        responseStyle = (try? c.decode(SiriResponseStyle.self, forKey: .responseStyle)) ?? .quick
        automaticallyContinues = (try? c.decode(Bool.self, forKey: .automaticallyContinues)) ?? true
    }

    public func requestOptions(app: ChatPreferences, thinking: Bool, plan: SiriConversationPlan) -> (preferences: ChatPreferences, thinking: Bool) {
        var options = app
        var reasoning = thinking
        switch responseStyle {
        case .quick: options.answerLength = .short; reasoning = false
        case .balanced: options.answerLength = .medium; reasoning = false
        case .followApp: break
        }
        if let length = plan.answerLength { options.answerLength = length }
        if let search = plan.webSearch { options.webSearch = search }
        if plan.writing { options.essayMode = true }
        return (options, reasoning)
    }
}

public enum SiriConversationMode: Sendable { case fresh, automatic, continuing }

/// Values supplied by Siri are validated identically by entity lookup and execution.
public enum SiriQuestionText {
    public static func validate(_ text: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SiriReplyError.emptyQuestion }
        guard value.count <= 4000 else { throw SiriReplyError.questionTooLong }
        return value
    }
}

public struct SiriConversationPlan: Sendable {
    public static let contextLifetime: TimeInterval = 600
    public let question: String
    public let startsNewConversation: Bool
    public let answerLength: AnswerLength?
    public let webSearch: Bool?
    public let writing: Bool

    public init(question: String, writing: Bool = false) throws {
        var value = try SiriQuestionText.validate(question)
        var fresh = false
        var length: AnswerLength?
        var search: Bool?
        // A separator distinguishes a control from a question about that phrase.
        for prefix in ["换个话题", "新问题", "重新开始", "新对话", "忘掉刚才"] {
            if let remainder = Self.remainder(value, after: prefix) {
                fresh = true; value = remainder; break
            }
        }
        for (prefix, option) in [("简短回答", AnswerLength.short), ("简单回答", .short), ("详细回答", .long)] {
            if let remainder = Self.remainder(value, after: prefix) {
                length = option; value = remainder; break
            }
        }
        // Follow-up requests retain their wording so the model knows what to expand.
        if length == nil {
            if ["再详细一点", "详细一点", "说详细一点", "展开讲讲", "详细说说"].contains(where: { value.hasPrefix($0) }) { length = .long }
            if ["再简短一点", "简短一点", "说短一点"].contains(where: { value.hasPrefix($0) }) { length = .short }
        }
        for (prefix, enabled) in [("不要联网", false), ("不联网回答", false), ("联网回答", true), ("联网搜索", true)] {
            if let remainder = Self.remainder(value, after: prefix) {
                search = enabled; value = remainder; break
            }
        }
        if value.hasPrefix("联网查") || value.hasPrefix("上网查") { search = true }
        let essay = value.range(of: #"^(请)?(帮我)?写(一篇|篇)?.{0,80}作文([，。,:：\s]|$)"#, options: .regularExpression) != nil
        self.question = try SiriQuestionText.validate(value)
        startsNewConversation = fresh
        answerLength = length; webSearch = search; self.writing = writing || essay
    }

    public func previousConversation(_ previous: Conversation?, mode: SiriConversationMode,
                                     preferences: SiriPreferences, now: Date = .now) throws -> Conversation? {
        if startsNewConversation || writing { return nil }
        switch mode {
        case .fresh: return nil
        case .continuing:
            guard let previous else { throw SiriReplyError.noPreviousConversation }
            return previous
        case .automatic:
            guard preferences.automaticallyContinues, let previous,
                  previous.messages.last?.role == .assistant, previous.messages.last?.state == .complete else { return nil }
            let age = now.timeIntervalSince(previous.updatedAt)
            return age >= 0 && age <= Self.contextLifetime ? previous : nil
        }
    }

    private static func remainder(_ value: String, after prefix: String) -> String? {
        guard value.hasPrefix(prefix) else { return nil }
        let suffix = value.dropFirst(prefix.count)
        guard let first = suffix.first, first.isWhitespace || "，。,:：".contains(first) else { return nil }
        return String(suffix.drop(while: { $0.isWhitespace || "，。,:：".contains($0) }))
    }
}
