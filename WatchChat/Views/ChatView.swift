// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

private enum ChatSheet: String, Identifiable {
    case compose, models, history, settings
    #if DEBUG
    case about
    #endif
    var id: String { rawValue }
}

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var speaker: ReplySpeaker
    @State private var sheet: ChatSheet?
    @State private var composeFromShortcut = false
    @State private var pendingRoute: WristChatRoute?

    var body: some View {
        NavigationStack {
            Group {
                if store.preferences.essayMode {
                    EssayWorkspaceView()
                } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 4) {
                            Text(store.selectedModel.shortTitle).lineLimit(1)
                            if store.deepThinking && store.activeProvider.supportsThinking {
                                Image(systemName: "brain").accessibilityLabel("深度思考已开启")
                            }
                            if store.searchEnabled {
                                Image(systemName: "globe").accessibilityLabel("联网搜索已开启")
                            }
                            if store.preferences.silent {
                                Image(systemName: "speaker.slash").accessibilityLabel("静音模式已开启")
                            }
                            if store.preferences.essayMode {
                                Text("作文").accessibilityLabel("作文模式已开启")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .id("top")

                        if let error = store.storageError {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }
                        if let error = store.modelError, !store.hasKey {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }

                        if store.current.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.hasKey ? (store.hasDraft(store.currentID) ? "草稿已保存" : "有什么想问的？") : "先连接 AI")
                                    .font(.headline)
                                Text(store.hasKey ? (store.hasDraft(store.currentID) ? store.draft : "点下方输入，听写或键盘都可以。") : "点左下设置填写密钥。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(store.hasDraft(store.currentID) ? 3 : nil)
                            }
                            .padding(.top, 10)
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(store.current.messages) { message in
                                MessageView(message: message,
                                    thinking: store.isThinking && message.state == .generating,
                                    canRetry: message.id == store.current.messages.last?.id && !store.isGenerating,
                                    textSize: store.preferences.textSize, showSources: store.preferences.showSources,
                                    speechRate: store.preferences.speechRate, canReadAloud: store.preferences.canReadAloud) {
                                    store.retry()
                                }
                                .equatable()
                                .id(message.id)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .onChange(of: store.current.messages.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .top) }
                }
                .onChange(of: store.currentID) { _, _ in
                    if store.current.messages.isEmpty { proxy.scrollTo("top", anchor: .top) }
                    else if let question = store.current.messages.last(where: { $0.role == .user }) {
                        proxy.scrollTo(question.id, anchor: .top)
                    }
                }
                .onAppear {
                    if let question = store.current.messages.last(where: { $0.role == .user }) {
                        proxy.scrollTo(question.id, anchor: .top)
                    }
                }
            }
                }
            }
            .navigationTitle(store.preferences.essayMode ? "作文" : "腕聊")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .history } label: { Image(systemName: "clock").foregroundStyle(.white) }
                        .accessibilityLabel("历史记录")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { sheet = .settings } label: { Image(systemName: "gearshape").foregroundStyle(.white) }
                        .accessibilityLabel("设置")
                    composeControl
                    Button { store.newConversation() } label: { Image(systemName: "plus").foregroundStyle(.white) }
                        .disabled(store.isGenerating || (store.current.messages.isEmpty && !store.hasDraft(store.currentID)))
                        .accessibilityLabel(store.preferences.essayMode ? "新作文，保留原稿" : "新对话，保留当前草稿")
                }
            }
            .sheet(item: $sheet, onDismiss: {
                composeFromShortcut = false
                if let route = pendingRoute {
                    pendingRoute = nil
                    openShortcut(route)
                }
            }) { destination in
                switch destination {
                case .compose: ComposeView(startsEditing: composeFromShortcut)
                case .models: ModelsView()
                case .history: HistoryView { sheet = nil }
                case .settings: NavigationStack { SettingsView() }
                #if DEBUG
                case .about: NavigationStack { AboutView() }
                #endif
                }
            }
            .onOpenURL { url in
                guard let route = WristChatRoute(url: url) else { return }
                if sheet != nil {
                    pendingRoute = route
                    sheet = nil
                } else { openShortcut(route) }
            }
            .onChange(of: store.currentID) { _, _ in speaker.stop() }
            .onChange(of: store.preferences.silent) { _, silent in if silent { speaker.stop() } }
            .onChange(of: store.preferences.essayMode) { _, _ in sheet = nil; speaker.stop() }
            .task {
                #if DEBUG
                if let screen = ProcessInfo.processInfo.environment["WRISTCHAT_SCREEN"] {
                    if screen == "compose" { store.draft = "请用一句话介绍你自己。" }
                    if screen == "table" { store.seedFeaturePreview() }
                    sheet = ChatSheet(rawValue: screen)
                }
                await store.runAcceptanceScenario()
                #endif
            }
        }
    }

    private func openShortcut(_ route: WristChatRoute) {
        switch route {
        case .ask:
            guard !store.isGenerating else { return }
            composeFromShortcut = true
            sheet = .compose
        case .history: sheet = .history
        case .settings: sheet = .settings
        }
    }

    @ViewBuilder
    private var composeControl: some View {
        if store.isGenerating {
            Button { store.stop() } label: { Image(systemName: "stop.fill").foregroundStyle(.black) }
                .tint(.orange)
                .accessibilityLabel("停止生成，保留已收到的回复")
        } else if !store.hasKey {
            Button { sheet = .settings } label: { Image(systemName: "key").foregroundStyle(.white) }
                .accessibilityLabel("配置 AI 密钥")
        } else if !store.draft.isEmpty {
            Button { sheet = .compose } label: {
                Image(systemName: "square.and.pencil").foregroundStyle(.black)
            }
                .tint(.mint)
                .accessibilityLabel("继续编辑已保存的草稿")
        } else {
            TextFieldLink(prompt: Text(store.preferences.essayMode ? "作文题目与要求" : "问 AI")) {
                Image(systemName: "square.and.pencil").foregroundStyle(.black)
            } onSubmit: { text in
                let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !prompt.isEmpty else { return }
                store.draft = prompt
                sheet = .compose
            }
            .tint(.mint)
            .accessibilityLabel("输入问题，直接打开系统听写或键盘")
        }
    }
}

private struct MessageView: View, Equatable {
    @State private var expanded = false
    @State private var sourcesPresented = false
    @EnvironmentObject private var speaker: ReplySpeaker
    let message: ChatMessage
    let thinking: Bool
    let canRetry: Bool
    let textSize: ReplyTextSize
    let showSources: Bool
    let speechRate: Double
    let canReadAloud: Bool
    let retry: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.thinking == rhs.thinking && lhs.canRetry == rhs.canRetry &&
        lhs.textSize == rhs.textSize && lhs.showSources == rhs.showSources && lhs.speechRate == rhs.speechRate && lhs.canReadAloud == rhs.canReadAloud
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .user {
                Text("你").font(.caption2).foregroundStyle(.secondary)
                Text(message.text).font(textSize == .large ? .title3 : .body).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(MiMoModel(id: message.modelID ?? "mimo").shortTitle)
                    .font(.caption2).foregroundStyle(.secondary)
                if !message.text.isEmpty {
                    ReplyContentView(text: message.text).equatable()
                        .font(textSize == .large ? .title3 : .body)
                }
                if message.state != .generating {
                    if (canReadAloud && !message.text.isEmpty) || (showSources && !(message.sources ?? []).isEmpty) {
                    HStack(spacing: 12) {
                        if !message.text.isEmpty && canReadAloud {
                            Button { speaker.toggle(message, rate: speechRate) } label: {
                                Label(speaker.messageID == message.id ? (speaker.paused ? "继续" : "暂停") : "朗读",
                                      systemImage: speaker.messageID == message.id && !speaker.paused ? "pause.fill" : "speaker.wave.2")
                            }
                            if speaker.messageID == message.id {
                                Button { speaker.stop() } label: { Image(systemName: "stop.fill") }
                                    .accessibilityLabel("停止朗读")
                            }
                        }
                        if showSources, let sources = message.sources, !sources.isEmpty {
                            Button { sourcesPresented = true } label: {
                                Label("来源 · \(sources.count)", systemImage: "link")
                            }.accessibilityLabel("查看全部 \(sources.count) 个搜索来源")
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    .buttonStyle(.plain).frame(minHeight: 36, alignment: .leading)
                    }
                    if canReadAloud, speaker.errorMessageID == message.id, let error = speaker.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                }
            }
            if message.state == .generating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(thinking ? "思考中…" : (message.text.isEmpty ? "等待回复…" : "正在回复…"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if let notice = message.notice {
                Text(notice).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canRetry && message.role == .assistant && message.state != .complete {
                Button("重新回答", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.bordered)
                    .tint(.mint)
            }
            if let attempts = message.previousReplies, !attempts.isEmpty {
                Button { expanded.toggle() } label: {
                    HStack {
                        Text("之前的回复（\(attempts.count)）")
                        Spacer(minLength: 4)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "收起之前的回复" : "展开之前的回复")
                if expanded { ForEach(attempts) { attempt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(MiMoModel(id: attempt.modelID ?? "mimo").shortTitle)
                                .font(.caption2).foregroundStyle(.secondary)
                            if !attempt.text.isEmpty { Text(attempt.text).font(.footnote) }
                            if let notice = attempt.notice {
                                Text(notice).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(message.role == .user ? 8 : 0)
        .background {
            if message.role == .user {
                RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12))
            }
        }
        .sheet(isPresented: $sourcesPresented) {
            NavigationStack { SourcesView(sources: message.sources ?? []) }
        }
    }
}
