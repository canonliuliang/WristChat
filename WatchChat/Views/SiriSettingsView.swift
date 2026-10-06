// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct SiriSettingsView: View {
    @EnvironmentObject private var store: ChatStore
    var body: some View {
        Form {
            Section {
                Picker("回答方式", selection: $store.siriPreferences.responseStyle) {
                    ForEach(SiriResponseStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.navigationLink)
                Toggle("自动接着聊", isOn: $store.siriPreferences.automaticallyContinues)
            } footer: {
                Text("十分钟内接续上次 Siri 问答。简洁快答与适度解释关闭深度思考；模型和联网沿用聊天设置。")
            }
            Section("怎么说") {
                Text("嘿 Siri，用腕聊回答")
                Text("也可以说“腕聊帮我”或“和腕聊聊聊”。Siri 询问时，直接说问题。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("已添加 AI 别名，可试说“用 AI 回答”。若 Siri 未识别，请用腕聊这个名字。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("接着问") {
                Text("再详细一点\n再简短一点\n换个话题，为什么天空是蓝色？")
                    .font(.footnote)
                Text("在提问入口说出这些要求即可；每次仍需唤起 Siri。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("这次的要求") {
                Text("联网回答，今天长沙天气怎样？\n不要联网，解释一下光合作用。")
                    .font(.footnote)
                Text("只改变这次请求，不修改聊天设置。回答与历史在后台保存，App 不会自动打开。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Siri 对话")
        .tint(.mint)
        #if DEBUG
        .modifier(AcceptanceTextSize())
        #endif
    }
}
