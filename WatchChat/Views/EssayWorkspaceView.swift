// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct EssayWorkspaceView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var selectedVersion: UUID?
    @State private var revising = false

    private var version: ChatMessage? {
        let versions = store.essayVersions
        return versions.first { $0.id == selectedVersion } ?? versions.last
    }

    var body: some View {
        let versions = store.essayVersions
        let version = versions.first { $0.id == selectedVersion } ?? versions.last
        List {
            if let version {
                let document = store.essayDocument(version)
                Section {
                    if versions.count > 1 {
                        Picker("稿件", selection: Binding(get: { version.id }, set: { selectedVersion = $0 })) {
                            ForEach(Array(versions.enumerated()), id: \.element.id) { index, message in
                                Text("第\(index + 1)稿 · \(store.essayDocument(message).wordCount)字").tag(message.id)
                            }
                        }.disabled(store.isGenerating)
                    }
                    NavigationLink {
                        EssayReaderView(message: version)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(document.title ?? "作文正文").font(.headline)
                            Text("正文 \(document.wordCount)字\(version.essayTarget.map { " · 目标\($0)" } ?? "")")
                                .font(.caption2).foregroundStyle(.mint)
                            Text(document.body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            Label("全文阅读", systemImage: "book").font(.caption2)
                        }.padding(.vertical, 3)
                    }.disabled(version.state == .generating)
                    if version.state != .generating {
                        Button { revising = true } label: { Label("改稿", systemImage: "pencil.line") }
                            .disabled(store.isGenerating || !store.hasKey)
                    }
                    if let sources = version.sources, store.preferences.showSources, !sources.isEmpty {
                        NavigationLink("来源 · \(sources.count)") { SourcesView(sources: sources) }
                    }
                } footer: { Text("字数由正文实际统计，不含标题、标点与空格。旧稿会保留。") }
            } else {
                Section {
                    Text("写一篇属于你的作文").font(.headline)
                    Text("输入题目与真实素材，默认约800字。写好后可以全文阅读，再调整开头、结尾或立意。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.isGenerating {
                ProgressView(store.isThinking ? "构思中…" : "写作中…")
            }
            if let last = store.current.messages.last, last.role == .assistant, let notice = last.notice {
                Text(notice).font(.caption).foregroundStyle(.orange)
                if !store.isGenerating, last.state != .complete { Button("重新生成") { store.retry() } }
            }
            if let error = store.modelError { Text(error).font(.caption).foregroundStyle(.orange) }
            if let error = store.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onChange(of: store.currentID) { _, _ in selectedVersion = nil }
        .onChange(of: store.isGenerating) { _, generating in if generating { selectedVersion = nil } }
        .sheet(isPresented: $revising) {
            if let version {
                NavigationStack {
                    List {
                        ForEach(EssayRevision.allCases) { action in
                            NavigationLink {
                                EssayRevisionView(message: version, action: action) {
                                    selectedVersion = nil; revising = false
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.title)
                                    Text(action.detail).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.navigationTitle("改稿")
                }
            }
        }
    }
}

private struct EssayRevisionView: View {
    @EnvironmentObject private var store: ChatStore
    let message: ChatMessage
    let action: EssayRevision
    let didBegin: () -> Void
    @State private var target: Int
    @State private var direction = ""
    @State private var error: String?

    init(message: ChatMessage, action: EssayRevision, didBegin: @escaping () -> Void) {
        self.message = message; self.action = action; self.didBegin = didBegin
        _target = State(initialValue: action.targetCount(for: EssayDocument(message.text).wordCount))
    }

    var body: some View {
        Form {
            Section {
                Text(action.detail).font(.caption).foregroundStyle(.secondary)
                TextField(action == .theme ? "新的立意（选填）" : "补充要求（选填）", text: $direction, axis: .vertical)
                    .onChange(of: direction) { _, value in if value.count > 400 { direction = String(value.prefix(400)) } }
                WritingTargetControl(target: $target)
            } footer: { Text("修改后生成完整新稿，原稿保留；事实与人物关系保持。") }
            Button("生成新稿") {
                if store.reviseEssay(message.id, action: action, target: target, direction: direction) { didBegin() }
                else { error = store.modelError ?? "暂时无法改稿，请检查连接与原稿。" }
            }.disabled(store.isGenerating)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.navigationTitle(action.title)
    }
}

struct EssayReaderView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var speaker: ReplySpeaker
    let message: ChatMessage
    private let document: EssayDocument
    private let bookmarkKey: String
    @State private var paragraph: Int?

    init(message: ChatMessage) {
        self.message = message
        let document = EssayDocument(message.text); self.document = document
        let key = "essayReading.\(message.id)"; bookmarkKey = key
        let saved = min(max(0, UserDefaults.standard.integer(forKey: key)), max(0, document.paragraphs.count - 1))
        _paragraph = State(initialValue: saved == 0 ? nil : saved)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(document.paragraphs.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        if index == 0 {
                            Text(document.title ?? "作文").font(.headline)
                            Text("正文 \(document.wordCount)字").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(document.paragraphs[index])
                            .font(store.preferences.textSize == .large ? .title3 : .body)
                            .fixedSize(horizontal: false, vertical: true)
                        if index == document.paragraphs.count - 1, store.preferences.canReadAloud {
                            Button { speaker.toggle(message, rate: store.preferences.speechRate) } label: {
                                Label(speaker.messageID == message.id ? (speaker.paused ? "继续" : "暂停") : "朗读", systemImage: "speaker.wave.2")
                            }.font(.caption).buttonStyle(.bordered)
                            if speaker.messageID == message.id {
                                Button("停止朗读") { speaker.stop() }.font(.caption)
                            }
                            if speaker.errorMessageID == message.id, let error = speaker.error {
                                Text(error).font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }.id(index)
                }
            }.scrollTargetLayout().padding(.horizontal, 10).padding(.bottom, 16)
        }
        .scrollPosition(id: $paragraph, anchor: .top)
        .onChange(of: paragraph) { _, value in if let value { UserDefaults.standard.set(value, forKey: bookmarkKey) } }
        .navigationTitle("全文阅读")
    }
}
