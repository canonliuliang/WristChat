// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var deletion: Conversation?
    let selected: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.histories.isEmpty {
                        Text("对话会自动保存到这里。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(store.histories) { conversation in
                        Button {
                            store.openConversation(conversation.id)
                            selected()
                        } label: {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(store.historyTitle(conversation)).font(.body).lineLimit(2)
                                    if store.hasDraft(conversation.id) {
                                        Text("有草稿").font(.caption2).foregroundStyle(.mint)
                                    } else {
                                        Text(HistoryTime.label(for: conversation.updatedAt))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                if conversation.id == store.currentID {
                                    Image(systemName: "checkmark").font(.caption).foregroundStyle(.mint)
                                }
                            }
                        }
                        .disabled(store.isGenerating)
                        .swipeActions {
                            Button(role: .destructive) { deletion = conversation } label: {
                                Label("删除", systemImage: "trash")
                            }.disabled(store.isGenerating)
                        }
                    }
                } footer: {
                    if store.isGenerating { Text("回复完成或停止后，可以切换对话。") }
                }
            }
            .navigationTitle("历史")
            .confirmationDialog("删除这段对话？", isPresented: Binding(
                get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                    Button("删除对话", role: .destructive) {
                        if let deletion { store.deleteConversation(deletion.id) }
                        deletion = nil
                    }
                }
        }
        #if DEBUG
        .modifier(AcceptanceTextSize())
        #endif
    }
}
