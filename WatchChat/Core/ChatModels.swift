// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

public enum MessageRole: String, Codable, Sendable {
    case user, assistant
}

public enum MessageState: String, Codable, Sendable {
    case complete, generating, failed, cancelled, interrupted, truncated
}

public struct ReplyAttempt: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let modelID: String?
    public let state: MessageState
    public let notice: String?
    public let date: Date
    public let sources: [SearchSource]?

    public init(message: ChatMessage) {
        id = message.id
        text = message.text
        modelID = message.modelID
        state = message.state
        notice = message.notice
        date = message.date
        sources = message.sources
    }
}

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var role: MessageRole
    public var text: String
    public var date: Date
    public var modelID: String?
    public var state: MessageState
    public var notice: String?
    /// Optional so existing personal histories decode without migration.
    public var previousReplies: [ReplyAttempt]?
    public var sources: [SearchSource]?
    public var providerName: String?
    public var isEssay: Bool?
    public var essayTarget: Int?

    public init(id: UUID = UUID(), role: MessageRole, text: String,
                date: Date = .now, modelID: String? = nil,
                state: MessageState = .complete, notice: String? = nil,
                previousReplies: [ReplyAttempt]? = nil, sources: [SearchSource]? = nil,
                providerName: String? = nil, isEssay: Bool? = nil, essayTarget: Int? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.modelID = modelID
        self.state = state
        self.notice = notice
        self.previousReplies = previousReplies
        self.sources = sources
        self.providerName = providerName
        self.isEssay = isEssay
        self.essayTarget = essayTarget
    }
}

public struct Conversation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var messages: [ChatMessage]
    public var updatedAt: Date
    public var writingWorkspace: Bool?

    public init(id: UUID = UUID(), messages: [ChatMessage] = [], updatedAt: Date = .now, writingWorkspace: Bool? = nil) {
        self.id = id
        self.messages = messages
        self.updatedAt = updatedAt
        self.writingWorkspace = writingWorkspace
    }

    public var isWriting: Bool {
        writingWorkspace ?? (messages.first(where: { $0.role == .user })?.text.contains("作文") == true)
    }

    public var title: String {
        guard let first = messages.first(where: { $0.role == .user }) else { return "新对话" }
        let text = first.text.replacingOccurrences(of: "\n", with: " ")
        return text.count > 24 ? String(text.prefix(24)) + "…" : text
    }

    public mutating func recoverInterruptedResponses() {
        for index in messages.indices where messages[index].state == .generating {
            messages[index].state = .interrupted
            messages[index].notice = "上次回复被中断，可以重试。"
        }
    }
}

public struct MiMoModel: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String?
    public init(id: String) { self.id = id; self.name = nil }
    public init(id: String, name: String?) { self.id = id; self.name = name }

    public var title: String {
        if let name, !name.isEmpty { return name.replacingOccurrences(of: "-", with: " ") }
        if id == "deepseek-flash" { return "DeepSeek Flash" }
        if id == "deepseek-v4-pro" { return "DeepSeek V4 Pro" }
        if id == "deepseek-chat" { return "DeepSeek Chat" }
        if id == "deepseek-reasoner" { return "DeepSeek Reasoner" }
        if !id.hasPrefix("mimo-") { return id }
        return id.replacingOccurrences(of: "mimo-", with: "MiMo ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "v2", with: "V2")
            .replacingOccurrences(of: "flash", with: "Flash")
            .replacingOccurrences(of: "pro", with: "Pro")
            .replacingOccurrences(of: "omni", with: "Omni")
            .replacingOccurrences(of: "ultraspeed", with: "UltraSpeed")
    }

    public var shortTitle: String { title.replacingOccurrences(of: "MiMo ", with: "") }

    public var detail: String {
        switch id {
        case "mimo-v2.6-flash": return "日常问答、翻译与轻量写作，优先快速回应。"
        case "mimo-v2.6-pro": return "适合复杂推理、代码与细致写作，回答更充分。"
        case "mimo-v2.6-pro-ultraspeed": return "Pro 能力的加速版本，适合需要较快输出的长回答。"
        case "mimo-v2.5": return "上一代通用模型，保留旧对话选择；日常提问建议用 V2.6 Flash。"
        case "mimo-v2.5-pro": return "上一代 Pro，保留旧习惯；复杂问题建议用 V2.6 Pro。"
        case "deepseek-flash", "deepseek-v4-flash": return "适合日常问答、翻译与写作，可按需要开启深度思考。"
        case "deepseek-v4-pro": return "适合复杂分析、代码与精细写作，可开启深度思考。"
        case "deepseek-chat": return "兼容旧客户端的对话名称，建议使用当前 Flash 模型。"
        case "deepseek-reasoner": return "兼容旧客户端的推理名称，优先使用当前模型与思考开关。"
        default: return "由提供商返回的模型；本 App 使用文字对话能力。"
        }
    }

    public var isLegacy: Bool {
        (id.hasPrefix("mimo-v2") && !id.hasPrefix("mimo-v2.6")) ||
            ["deepseek-chat", "deepseek-reasoner"].contains(id)
    }

    public static func isChatModel(_ id: String) -> Bool {
        let name = id.lowercased()
        return name.hasPrefix("mimo-") &&
            !["tts", "asr", "voice", "embedding", "rerank", "audio"].contains(where: name.contains)
    }

    /// Used offline until the authenticated model list is available.
    public static let defaults = ["mimo-v2.6-flash", "mimo-v2.6-pro", "mimo-v2.6-pro-ultraspeed",
                                  "mimo-v2.5", "mimo-v2.5-pro"].map(MiMoModel.init)

    public static func preferred(in models: [MiMoModel]) -> String? {
        for id in ["mimo-v2.6-flash", "mimo-v2.5", "mimo-v2-flash"] {
            if models.contains(where: { $0.id == id }) { return id }
        }
        return models.first?.id
    }
}

public struct APIMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public enum ChatContext {
    /// Retain complete exchanges only. An interrupted response must never become a complete answer.
    public static func messages(history: [ChatMessage], prompt: String,
                                characterBudget: Int = 16_000, date: Date = .now,
                                preferences: ChatPreferences = .init()) -> [APIMessage] {
        var pairs: [[APIMessage]] = []
        var user: ChatMessage?
        for message in history {
            if message.role == .user {
                user = message
            } else if let question = user {
                if message.state == .complete && !message.text.isEmpty {
                    pairs.append([APIMessage(role: "user", content: question.text),
                                  APIMessage(role: "assistant", content: message.text)])
                }
                user = nil
            }
        }
        var selected: [[APIMessage]] = []
        var count = prompt.count
        for pair in pairs.suffix(preferences.contextDepth.exchanges).reversed() {
            let size = pair.reduce(0) { $0 + $1.content.count }
            guard count + size <= characterBudget else { break }
            selected.insert(pair, at: 0)
            count += size
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        let search = preferences.webSearch ? "已提供联网搜索工具，涉及实时信息时依据搜索来源回答；搜索失败时明确说明，不能编造来源。" : "本次没有联网搜索工具，不要声称查到了实时信息或编造搜索来源。"
        let essay = preferences.essayMode ? "\n\(EssayWriting.instruction)" : ""
        let length = preferences.essayMode ? "仅普通问答遵循：\(preferences.answerLength.instruction)作文类任务忽略普通问答的字数限制，遵循下面的作文规则。" : preferences.answerLength.instruction
        let instruction = "你是用户 Apple Watch 上的个人 AI 助手。\(preferences.language.instruction)\(length)适合小屏阅读，用户明确指定篇幅时优先遵从。适合比较的数据可以使用 Markdown 表格，列标题简短，单元格避免冗长。今天是 \(formatter.string(from: date))。\(search)\n用户的个人偏好：\(preferences.customInstruction.prefix(600))\(essay)"
        return [APIMessage(role: "system", content: instruction)] + selected.flatMap { $0 } +
            [APIMessage(role: "user", content: prompt)]
    }
}
