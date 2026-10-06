// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

public enum ProviderProtocol: String, Codable, CaseIterable, Sendable {
    case mimo, deepSeek, openAICompatible
}

/// Configuration contains no credentials. Keys are stored separately per provider.
public struct AIProvider: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var apiProtocol: ProviderProtocol
    public var manualModelIDs: [String]

    public init(id: String = UUID().uuidString, name: String, baseURL: String,
                apiProtocol: ProviderProtocol = .openAICompatible, manualModelIDs: [String] = []) {
        self.id = id; self.name = name; self.baseURL = baseURL
        self.apiProtocol = apiProtocol; self.manualModelIDs = manualModelIDs
    }

    public static let mimo = AIProvider(id: "mimo", name: "小米 MiMo",
        baseURL: "https://api.xiaomimimo.com/v1/", apiProtocol: .mimo)
    public static let deepSeek = AIProvider(id: "deepseek", name: "DeepSeek",
        baseURL: "https://api.deepseek.com/", apiProtocol: .deepSeek)
    public var isBuiltIn: Bool { id == Self.mimo.id || id == Self.deepSeek.id }
    public var supportsSearch: Bool { apiProtocol == .mimo }
    public var supportsThinking: Bool { apiProtocol != .openAICompatible }

    public func endpoint(_ path: String) throws -> URL {
        guard let parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let url = parts.url, !parts.path.hasSuffix("chat/completions") else {
            throw ProviderError.invalidURL
        }
        return url.appendingPathComponent(path)
    }

    public var fallbackModels: [MiMoModel] {
        if !manualModelIDs.isEmpty { return manualModelIDs.map { MiMoModel(id: $0) } }
        switch apiProtocol {
        case .mimo: return MiMoModel.defaults
        case .deepSeek: return [MiMoModel(id: "deepseek-flash", name: "DeepSeek V4.1 Flash"),
                               MiMoModel(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro")]
        case .openAICompatible: return []
        }
    }

    public func acceptsModel(_ id: String) -> Bool {
        if apiProtocol == .mimo { return MiMoModel.isChatModel(id) }
        return !id.isEmpty && !["embedding", "rerank", "whisper", "tts", "dall-e"].contains(where: id.lowercased().contains)
    }

    public var defaultModelID: String {
        switch apiProtocol {
        case .mimo: "mimo-v2.6-flash"
        case .deepSeek: "deepseek-flash"
        case .openAICompatible: manualModelIDs.first ?? ""
        }
    }
}

public enum ProviderError: LocalizedError, Equatable {
    case invalidURL, searchUnsupported, invalidModel, invalidName
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "填写 HTTPS API 基础地址，不含密钥、查询参数或 chat/completions。"
        case .searchUnsupported: "当前提供商未接入网页搜索，请切换到 MiMo 使用联网搜索。"
        case .invalidModel: "请刷新模型或填写该提供商的模型 ID。"
        case .invalidName: "请填写提供商名称。"
        }
    }
}
