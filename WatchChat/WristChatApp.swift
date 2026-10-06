// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI
import AppIntents

@main
struct WristChatApp: App {
    @StateObject private var store = ChatStore.shared
    @StateObject private var speaker = ReplySpeaker()
    @Environment(\.scenePhase) private var scenePhase

    init() { WristChatShortcuts.updateAppShortcutParameters() }

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(store)
                .environmentObject(speaker)
                .tint(Color(white: 0.22))
                #if DEBUG
                .modifier(AcceptanceTextSize())
                #endif
                .task { await store.refreshModels(force: false) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        store.stop(background: true); store.save()
                        speaker.stop()
                        Task { await store.flushHistory() }
                    }
                }
        }
    }
}

#if DEBUG
struct AcceptanceTextSize: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.environment["WRISTCHAT_LARGE_TYPE"] == "1" {
            content.dynamicTypeSize(.accessibility5)
        } else {
            content
        }
    }
}
#endif
