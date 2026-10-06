// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation
import Security

enum Credentials {
    private static func service(_ provider: AIProvider) -> String {
        provider.id == AIProvider.mimo.id ? "com.liuliang.WristChat.mimo" : "com.liuliang.WristChat.provider.\(provider.id)"
    }
    private static let account = "api-key"

    static func read(provider: AIProvider = .mimo) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(provider),
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw CredentialError.storage(status) }
        return key
    }

    static func save(_ rawKey: String, provider: AIProvider = .mimo) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 8, key.count <= 4096,
              (provider.apiProtocol == .openAICompatible || key.hasPrefix("sk-")),
              !key.contains(where: { $0.isWhitespace }) else { throw CredentialError.format }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(provider),
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw CredentialError.storage(status) }
        } else if update != errSecSuccess { throw CredentialError.storage(update) }
    }

    static func bootstrap() throws {
        guard let url = Bundle.main.url(forResource: "BootstrapCredentials", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else { return }
        for (provider, field) in [(AIProvider.mimo, "MiMoAPIKey"), (.deepSeek, "DeepSeekAPIKey")] {
            if try read(provider: provider).isEmpty, let key = value[field], !key.isEmpty {
                try save(key, provider: provider)
            }
        }
    }

    enum CredentialError: LocalizedError {
        case format, storage(OSStatus)
        var errorDescription: String? {
            switch self {
            case .format: "请填写完整的 API 密钥，不含空格。"
            case .storage: "无法读取或保存密钥，请解锁手表后重试。"
            }
        }
    }
}
