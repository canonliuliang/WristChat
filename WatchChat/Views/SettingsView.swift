// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    var body: some View {
        Form {
            Section {
                Picker("工作方式", selection: Binding(get: { store.preferences.essayMode }, set: { store.setWritingMode($0) })) {
                    Text("聊天").tag(false)
                    Text("作文工作台").tag(true)
                }
                .pickerStyle(.navigationLink)
                .disabled(store.isGenerating)
                if !store.preferences.essayMode { AnswerLengthControl(selection: $store.preferences.answerLength) }
            } header: { Text("对话") } footer: {
                if store.preferences.essayMode { Text("独立写作与全文阅读，默认约800字。") }
            }
            Section("回复") {
                Toggle("静音模式", isOn: $store.preferences.silent)
                Toggle("深度思考", isOn: $store.deepThinking)
                    .disabled(!store.activeProvider.supportsThinking)
                Toggle("联网搜索", isOn: $store.preferences.webSearch)
                    .disabled(!store.canSearch)
            }
            Section("使用偏好") {
                NavigationLink("显示与触感") { DisplaySettingsView() }
                NavigationLink("回答朗读") { SpeechSettingsView() }
                NavigationLink("对话偏好") { ConversationSettingsView() }
            }
            Section("AI 服务") {
                NavigationLink("提供商") { ProvidersView() }
                NavigationLink("网络与密钥") { ConnectionSettingsView() }
            }
            Section { NavigationLink("关于腕聊") { AboutView() } }
        }
        .navigationTitle("设置")
        .tint(.mint)
        #if DEBUG
        .modifier(AcceptanceTextSize())
        #endif
    }
}

private struct DisplaySettingsView: View {
    @EnvironmentObject private var store: ChatStore
    var body: some View {
        Form {
            Section {
                Picker("聊天字号", selection: $store.preferences.textSize) {
                    ForEach(ReplyTextSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.navigationLink)
                Toggle("显示搜索来源", isOn: $store.preferences.showSources)
                Toggle("回复触感提示", isOn: $store.preferences.haptics)
                    .disabled(store.preferences.silent)
            } footer: {
                Text("字号也跟随系统文字大小。静音关闭回复触感并隐藏朗读按钮。表格可左右滑动查看。")
            }
            Section("预览") {
                Text("先给结论，再看细节。")
                    .font(store.preferences.textSize == .large ? .title3 : .body)
            }
        }.navigationTitle("显示与触感")
    }
}

private struct ConversationSettingsView: View {
    @EnvironmentObject private var store: ChatStore
    var body: some View {
        Form {
            Section {
                Picker("上下文", selection: $store.preferences.contextDepth) {
                    ForEach(ContextDepth.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.navigationLink)
                Picker("回答语言", selection: $store.preferences.language) {
                    ForEach(AnswerLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.navigationLink)
            } footer: { Text("上下文只包含完整问答。关闭后每次独立回答，已有历史仍保留。") }
            Section {
                TextField("例如：少用专业术语", text: Binding(
                    get: { store.preferences.customInstruction },
                    set: { store.preferences.customInstruction = String($0.prefix(600)) }
                ), axis: .vertical)
                Text("\(store.preferences.customInstruction.count)/600字")
                    .font(.caption2).foregroundStyle(.secondary)
            } header: { Text("个人偏好") } footer: { Text("每次提问会带上这些偏好，可听写输入。") }
        }.navigationTitle("对话偏好")
    }
}

private struct ConnectionSettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var newKey = ""
    @State private var feedback: String?
    var body: some View {
        Form {
            Section {
                Toggle("允许蜂窝网络", isOn: $store.preferences.allowsCellular)
            } footer: { Text("关闭后仅使用非计费连接，如普通 Wi-Fi。关闭联网搜索仍需连接 AI 服务。") }
            Section("联网搜索") {
                Text(store.activeProvider.apiProtocol == .deepSeek
                     ? "DeepSeek 由 MiMo 检索资料后回答，需配置 MiMo 密钥并开通搜索服务。"
                     : (store.canSearch ? "使用 MiMo 联网服务插件，需在控制台开通，并另计用量。" : "当前提供商尚未接入网页搜索。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("\(store.activeProvider.name) 密钥") {
                Label(store.hasKey ? "已配置" : "未配置", systemImage: store.hasKey ? "checkmark" : "key")
                    .font(.footnote).foregroundStyle(store.hasKey ? Color.secondary : Color.orange)
                SecureField("填写新密钥", text: $newKey).disabled(store.isGenerating)
                    .accessibilityLabel("更换 \(store.activeProvider.name) API 密钥")
                Button("保存密钥") {
                    do {
                        try store.saveKey(newKey)
                        newKey = ""
                        feedback = "密钥已保存。"
                        Task { await store.refreshModels() }
                    } catch { feedback = error.localizedDescription }
                }.disabled(newKey.isEmpty || store.isGenerating)
                if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
                Button {
                    Task {
                        await store.refreshModels()
                        feedback = store.modelError ?? "连接成功，找到 \(store.models.count) 个聊天模型。"
                    }
                } label: {
                    if store.isRefreshingModels { ProgressView("验证中…") }
                    else { Text("验证连接与刷新模型") }
                }.disabled(store.isRefreshingModels || !store.hasKey)
            }
        }.navigationTitle("网络与密钥")
    }
}
