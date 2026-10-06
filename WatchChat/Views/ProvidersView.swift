// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject private var store: ChatStore
    var body: some View {
        List {
            Section {
                ForEach(store.providers) { provider in
                    NavigationLink { ProviderEditor(provider: provider) } label: {
                        HStack {
                            Text(provider.name)
                            Spacer(minLength: 4)
                            if provider.id == store.activeProviderID { Image(systemName: "checkmark").foregroundStyle(.mint) }
                        }
                    }
                }
                NavigationLink { ProviderEditor(provider: nil) } label: { Label("添加提供商", systemImage: "plus") }
            } footer: { Text("支持 OpenAI 兼容的文字聊天接口，每个提供商单独保存密钥。") }
        }.navigationTitle("提供商")
    }
}

private struct ProviderEditor: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider?
    @State private var configuration: AIProvider
    @State private var key = ""
    @State private var modelIDs: String
    @State private var feedback: String?

    init(provider: AIProvider?) {
        self.provider = provider
        _configuration = State(initialValue: provider ?? AIProvider(name: "", baseURL: "https://"))
        _modelIDs = State(initialValue: provider?.manualModelIDs.joined(separator: ", ") ?? "")
    }

    var body: some View {
        Form {
            if let provider {
                Section {
                    Button(provider.id == store.activeProviderID ? "当前正在使用" : "使用这个提供商") {
                        store.selectProvider(provider.id); dismiss()
                    }.disabled(store.isGenerating || provider.id == store.activeProviderID)
                }
            }
            Section {
                TextField("名称", text: $configuration.name).disabled(configuration.isBuiltIn)
                TextField("API 基础地址", text: $configuration.baseURL).disabled(configuration.isBuiltIn)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } footer: {
                Text(configuration.isBuiltIn ? "使用官方接口。" : "例如 https://example.com/v1/。更换地址时需重新填写密钥。")
            }
            Section {
                SecureField(provider == nil ? "API 密钥" : "填写新密钥（可选）", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !configuration.isBuiltIn {
                    TextField("模型 ID，逗号分隔", text: $modelIDs)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            } header: { Text("连接") } footer: {
                Text(configuration.isBuiltIn ? "密钥留空可保留已配置的值。" : "留空模型 ID 会从接口获取；接口不支持模型列表时可手动填写。")
            }
            Section {
                Button("保存并使用") {
                    configuration.name = String(configuration.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                    configuration.baseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    configuration.manualModelIDs = Array(Set(modelIDs.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
                    do {
                        try store.configureProvider(configuration, key: key)
                        key = ""; feedback = "已保存，正在获取模型。"
                        Task { await store.refreshModels(); feedback = store.modelError ?? "连接成功，模型已更新。" }
                    } catch { feedback = error.localizedDescription }
                }.disabled(store.isGenerating || (provider == nil && key.isEmpty))
                if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
            }
        }.navigationTitle(provider?.name ?? "添加提供商")
        .disabled(store.isGenerating)
    }
}
