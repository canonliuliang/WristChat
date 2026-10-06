// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("提供商", selection: Binding(get: { store.activeProviderID }, set: { store.selectProvider($0) })) {
                        ForEach(store.providers) { Text($0.name).tag($0.id) }
                    }.disabled(store.isGenerating)
                }
                Section {
                    ForEach(store.orderedModels.filter { !$0.isLegacy }) { model in modelRow(model) }
                    let old = store.orderedModels.filter(\.isLegacy)
                    if !old.isEmpty {
                        NavigationLink {
                            List { ForEach(old) { model in modelRow(model) } }.navigationTitle("旧版模型")
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("旧版模型 · \(old.count)")
                                Text(old.contains { $0.id == store.selectedModelID } ? "当前选择在这里" : "保留旧版本，点按查看")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if store.models.isEmpty { Text("尚无模型，请刷新或在提供商设置中填写模型 ID。").font(.caption) }
                } header: { Text(store.activeProvider.name) } footer: { Text("下一条消息生效，保留当前对话。") }
                Section {
                    Button { Task { await store.refreshModels() } } label: {
                        if store.isRefreshingModels { ProgressView("正在刷新…") }
                        else { Label("刷新模型", systemImage: "arrow.clockwise") }
                    }.disabled(store.isRefreshingModels)
                    NavigationLink("管理提供商") { ProvidersView() }
                    if let error = store.modelError { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }.navigationTitle("模型")
        }
        #if DEBUG
        .modifier(AcceptanceTextSize())
        #endif
    }

    private func modelRow(_ model: MiMoModel) -> some View {
        Button { store.selectedModelID = model.id; dismiss() } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.shortTitle).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(model.detail).font(.caption2).foregroundStyle(.secondary)
                }
                if model.id == store.selectedModelID { Image(systemName: "checkmark").foregroundStyle(.mint) }
            }.padding(.vertical, 3)
        }.disabled(store.isGenerating)
        .accessibilityLabel("\(model.title)，\(model.detail)\(model.id == store.selectedModelID ? "，已选择" : "")")
    }
}
