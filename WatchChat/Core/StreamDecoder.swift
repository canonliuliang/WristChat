// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

public enum StreamEvent: Equatable, Sendable {
    case text(String)
    case thinking
    case sources([SearchSource])
    case searchFailed
    case finished(String)
    case done
}

public enum MiMoError: Error, LocalizedError, Equatable, Sendable {
    case missingKey
    case http(Int, String?)
    case invalidResponse
    case emptyResponse
    case disconnected
    case server(String)
    case searchUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingKey: "请先在设置中填写当前提供商的 API 密钥。"
        case .http(let status, _):
            switch status {
            case 401, 403: "密钥无效或无权使用此模型，请检查设置。"
            case 402: "当前提供商账户余额不足，请到其开放平台查看。"
            case 404: "此模型暂不可用，请刷新模型列表。"
            case 429: "请求太频繁或额度不足，请稍后重试。"
            case 500...599: "AI 服务暂时繁忙，请稍后重试。"
            default: "AI 请求失败（\(status)），请稍后重试。"
            }
        case .invalidResponse: "收到的回复格式无法识别，请重试。"
        case .emptyResponse: "模型没有返回正文，请关闭深度思考或换个模型再试。"
        case .disconnected: "连接中断，已保留收到的内容。"
        case .server: "AI 未能完成回复，请重试或切换模型。"
        case .searchUnavailable: "联网搜索不可用，请检查 MiMo 控制台是否已开通联网服务插件，或关闭联网后重试。"
        }
    }
}

/// SSE events are delimited by a blank line; comments and event labels don't contain reply text.
public struct StreamDecoder: Sendable {
    private var dataLines: [String] = []
    private var eventName: String?
    public init() {}

    public mutating func append(line rawLine: String) throws -> [StreamEvent] {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return try flush() }
        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            dataLines.append(value)
        }
        return []
    }

    public mutating func flush() throws -> [StreamEvent] {
        let payload = dataLines.joined(separator: "\n")
        let event = eventName
        dataLines.removeAll(keepingCapacity: true)
        eventName = nil
        guard !payload.isEmpty else { return [] }
        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" { return [.done] }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiMoError.invalidResponse
        }
        if event == "error" || object["error"] != nil { throw MiMoError.server("stream_error") }
        guard let choices = object["choices"] as? [[String: Any]] else {
            // Usage-only chunks are allowed at the end of a stream.
            if object["usage"] != nil { return [] }
            throw MiMoError.invalidResponse
        }
        guard let choice = choices.first else { return [] }
        let delta = choice["delta"] as? [String: Any] ?? [:]
        var events: [StreamEvent] = []
        if let annotations = delta["annotations"] as? [[String: Any]] {
            let sources = annotations.compactMap { item -> SearchSource? in
                guard let url = item["url"] as? String else { return nil }
                return SearchSource(url: url, title: item["title"] as? String ?? "", site: item["site_name"] as? String ?? "")
            }
            if !sources.isEmpty { events.append(.sources(sources)) }
        }
        if let error = delta["error_message"] as? String, !error.isEmpty { events.append(.searchFailed) }
        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            events.append(.thinking)
        }
        if let text = delta["content"] as? String, !text.isEmpty { events.append(.text(text)) }
        if let reason = choice["finish_reason"] as? String { events.append(.finished(reason)) }
        return events
    }
}
