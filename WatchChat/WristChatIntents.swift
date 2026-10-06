// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import AppIntents
import Foundation

struct AskWristChatIntent: LongRunningIntent {
    static let title: LocalizedStringResource = "用腕聊提问"
    static let description = IntentDescription("直接在 Siri 中提问并获得 AI 回答，无需打开腕聊。使用 App 中选好的模型与联网设置。")
    static var supportedModes: IntentModes { .background }
    static let openAppWhenRun = false
    @Parameter(title: "问题", requestValueDialog: "你想问腕聊什么？") var question: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let reply = try await performBackgroundTask {
            progress.totalUnitCount = -1
            progress.localizedDescription = "正在回答"
            return try await ChatStore.shared.answerSiri(question: question, progress: { count in
                progress.completedUnitCount = Int64(count)
            })
        }
        return .result(value: reply.resultText, dialog: "\(reply.spokenText)")
    }
}

struct ContinueWristChatIntent: LongRunningIntent {
    static let title: LocalizedStringResource = "继续问腕聊"
    static let description = IntentDescription("继续最近一次 Siri 对话，直接在 Siri 中返回回答。")
    static var supportedModes: IntentModes { .background }
    static let openAppWhenRun = false
    @Parameter(title: "追问", requestValueDialog: "你想继续问什么？") var question: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let reply = try await performBackgroundTask {
            progress.totalUnitCount = -1
            progress.localizedDescription = "正在回答追问"
            return try await ChatStore.shared.answerSiri(question: question, continuing: true, progress: { count in
                progress.completedUnitCount = Int64(count)
            })
        }
        return .result(value: reply.resultText, dialog: "\(reply.spokenText)")
    }
}

struct WriteWithWristChatIntent: LongRunningIntent {
    static let title: LocalizedStringResource = "用腕聊写作文"
    static let description = IntentDescription("说出题目、素材和要求，直接在 Siri 中生成作文，无需进入 App。")
    static var supportedModes: IntentModes { .background }
    static let openAppWhenRun = false
    @Parameter(title: "题目与要求", requestValueDialog: "作文题目是什么？也可以一起说素材和要求。") var assignment: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let reply = try await performBackgroundTask {
            progress.totalUnitCount = -1
            progress.localizedDescription = "正在写作文"
            return try await ChatStore.shared.answerSiri(question: assignment, writing: true, progress: { count in
                progress.completedUnitCount = Int64(count)
            })
        }
        return .result(value: reply.resultText, dialog: "\(reply.spokenText)")
    }
}

struct WristChatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskWristChatIntent(), phrases: ["用\(.applicationName)提问", "问\(.applicationName)"],
            shortTitle: "提问", systemImageName: "mic")
        AppShortcut(intent: ContinueWristChatIntent(), phrases: ["继续问\(.applicationName)", "用\(.applicationName)继续对话"],
            shortTitle: "继续追问", systemImageName: "bubble.left.and.bubble.right")
        AppShortcut(intent: WriteWithWristChatIntent(), phrases: ["用\(.applicationName)写作文"],
            shortTitle: "写作文", systemImageName: "pencil.line")
    }
}
