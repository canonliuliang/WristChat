// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

public enum AnswerLength: String, Codable, CaseIterable, Sendable {
    case short, medium, long
    public var sliderValue: Double { switch self { case .short: 0; case .medium: 1; case .long: 2 } }
    public init(sliderValue: Double) {
        let value = sliderValue.isFinite ? min(2, max(0, sliderValue)).rounded() : 0
        self = value == 2 ? .long : (value == 1 ? .medium : .short)
    }
    public var title: String {
        switch self { case .short: "短回答"; case .medium: "中回答"; case .long: "长回答" }
    }
    public var instruction: String {
        switch self {
        case .short: "先给结论，通常控制在150字以内，避免不必要的展开。"
        case .medium: "先给结论，再适度解释，通常约300至500字，包含必要的例子，避免冗长。"
        case .long: "详细解释，提供必要的步骤、例子和依据，按主题分段；不必刻意缩短。"
        }
    }
}

public enum AnswerLanguage: String, Codable, CaseIterable, Sendable {
    case chinese, english, automatic
    public var title: String {
        switch self { case .chinese: "简体中文"; case .english: "English"; case .automatic: "跟随提问" }
    }
    public var instruction: String {
        switch self { case .chinese: "默认用简体中文。"; case .english: "默认用英语。"; case .automatic: "使用用户提问的语言。" }
    }
}

public enum ContextDepth: String, Codable, CaseIterable, Sendable {
    case none, recent, extended
    public var title: String {
        switch self { case .none: "不记住上下文"; case .recent: "最近3轮"; case .extended: "最近8轮" }
    }
    public var exchanges: Int {
        switch self { case .none: 0; case .recent: 3; case .extended: 8 }
    }
}

public enum ReplyTextSize: String, Codable, CaseIterable, Sendable {
    case system, large
    public var title: String { self == .system ? "标准" : "较大" }
}

/// A single versioned preference value keeps request options consistent for each send.
public struct ChatPreferences: Codable, Equatable, Sendable {
    public var answerLength: AnswerLength = .short
    public var webSearch = false
    public var silent = false
    public var haptics = true
    public var contextDepth: ContextDepth = .extended
    public var language: AnswerLanguage = .chinese
    public var textSize: ReplyTextSize = .system
    public var allowsCellular = true
    public var showSources = true
    public var customInstruction = ""
    public var essayMode = false
    public var speechRate: Double = 1
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case answerLength, webSearch, silent, haptics, contextDepth, language, textSize
        case allowsCellular, showSources, customInstruction, essayMode, speechRate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answerLength = try c.decodeIfPresent(AnswerLength.self, forKey: .answerLength) ?? .short
        webSearch = try c.decodeIfPresent(Bool.self, forKey: .webSearch) ?? false
        silent = try c.decodeIfPresent(Bool.self, forKey: .silent) ?? false
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        contextDepth = try c.decodeIfPresent(ContextDepth.self, forKey: .contextDepth) ?? .extended
        language = try c.decodeIfPresent(AnswerLanguage.self, forKey: .language) ?? .chinese
        textSize = try c.decodeIfPresent(ReplyTextSize.self, forKey: .textSize) ?? .system
        allowsCellular = try c.decodeIfPresent(Bool.self, forKey: .allowsCellular) ?? true
        showSources = try c.decodeIfPresent(Bool.self, forKey: .showSources) ?? true
        customInstruction = try c.decodeIfPresent(String.self, forKey: .customInstruction) ?? ""
        essayMode = try c.decodeIfPresent(Bool.self, forKey: .essayMode) ?? false
        speechRate = min(1.4, max(0.7, try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? 1))
    }

    public var shouldNotify: Bool { !silent && haptics }
    public var canReadAloud: Bool { !silent }
    public func completionBudget(thinking: Bool) -> Int {
        // Reasoning tokens share this budget; don't starve thinking for a short answer.
        if essayMode { return thinking ? 16384 : 8192 }
        if thinking { return answerLength == .short ? 8192 : 16384 }
        switch answerLength { case .short: return 2048; case .medium: return 4096; case .long: return 8192 }
    }
}

public enum HistoryTime {
    /// Whole units only: avoids watchOS's second-by-second relative Text updates.
    public static func label(for date: Date, now: Date = .now) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return "刚刚" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))分钟前" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))小时前" }
        if elapsed < 604800 { return "\(Int(elapsed / 86400))天前" }
        return date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day())
    }
}

public struct SearchSource: Codable, Equatable, Identifiable, Sendable {
    public let url: URL
    public let title: String
    public let site: String
    public var id: String { url.absoluteString }
    public init?(url: String, title: String, site: String) {
        guard let address = URL(string: url), ["https", "http"].contains(address.scheme?.lowercased()),
              address.host != nil else { return nil }
        self.url = address
        self.title = title.isEmpty ? (address.host ?? "来源") : title
        self.site = site.isEmpty ? (address.host ?? "来源") : site
    }
}
