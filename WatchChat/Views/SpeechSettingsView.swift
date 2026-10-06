// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct SpeechSettingsView: View {
    @EnvironmentObject private var store: ChatStore
    var body: some View {
        Form {
            Section {
                Picker("语速", selection: $store.preferences.speechRate) {
                    Text("慢一些").tag(0.8)
                    Text("标准").tag(1.0)
                    Text("快一些").tag(1.2)
                }
                .pickerStyle(.navigationLink)
            } footer: {
                Text("非静音时，回复下方点“朗读”播放，可暂停或停止。静音会隐藏朗读并停止播放。音频跟随系统输出，可使用蓝牙耳机。进入后台会停止播放。")
            }
        }.navigationTitle("回答朗读")
    }
}
