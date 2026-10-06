// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct ComposeView: View {
    var startsEditing = false
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var modelPresented = false
    @FocusState private var inputFocused: Bool

    private var trimmed: String { store.draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Button { modelPresented = true } label: {
                        HStack(spacing: 4) {
                            Text(store.selectedModel.shortTitle)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("发送给 \(store.selectedModel.title)，点按切换模型")
                    if store.preferences.essayMode {
                        TextField("题目与写作要求", text: $store.draft, axis: .vertical)
                            .focused($inputFocused)
                        TextField("真实素材（选填）", text: Binding(get: { store.writingMaterial }, set: { store.writingMaterial = $0 }), axis: .vertical)
                        WritingTargetControl(target: Binding(get: { store.writingTarget }, set: { store.writingTarget = $0 }))
                        Text("开头点题并引出下文；最后两三段写感悟、主旨与立意。")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if editing || trimmed.isEmpty {
                        TextField("输入问题", text: $store.draft)
                            .focused($inputFocused)
                            .accessibilityLabel("编辑问题，支持系统听写和键盘")
                    } else {
                        Text(store.draft).font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if store.draft.count > (store.preferences.essayMode ? 1500 : 4000) {
                        Text(store.preferences.essayMode ? "写作要求超过1500字，请缩短后发送。" : "问题超过4000字，请缩短后发送。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .navigationTitle(store.preferences.essayMode ? "写作要求" : "确认发送")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { editing.toggle() } label: { Image(systemName: editing ? "checkmark" : "pencil") }
                        .accessibilityLabel(editing ? "完成修改" : "修改问题")
                    Button {
                        if store.preferences.essayMode ? store.sendEssay() : store.send(store.draft) { dismiss() }
                    } label: { Image(systemName: "arrow.up").foregroundStyle(.black) }
                        .tint(.mint)
                        .disabled(trimmed.isEmpty || trimmed.count > (store.preferences.essayMode ? 1500 : 4000) || store.isGenerating)
                        .accessibilityLabel("发送给 \(store.selectedModel.title)")
                }
            }
            .sheet(isPresented: $modelPresented) { ModelsView() }
            .onAppear {
                if startsEditing && trimmed.isEmpty { inputFocused = true }
            }
        }
        #if DEBUG
        .modifier(AcceptanceTextSize())
        #endif
    }
}
