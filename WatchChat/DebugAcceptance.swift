// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

#if DEBUG
import Foundation
import AppIntents

/// Development-only checks drive the real store on the watch simulator.
/// Disabled in Release; test output contains no credential or user content.
extension ChatStore {
    func runAcceptanceScenario() async {
        guard let scenario = ProcessInfo.processInfo.environment["WRISTCHAT_ACCEPTANCE"] else { return }
        guard !acceptanceHasRun else { return }
        acceptanceHasRun = true
        let savedPreferences = preferences
        let savedThinking = deepThinking
        if ["conversation", "cancelRetry"].contains(scenario) {
            preferences = .init()
            deepThinking = false
        }
        defer {
            if !["v15siri", "v14workspace", "v14preview", "v14sources"].contains(scenario) { preferences = savedPreferences }
            deepThinking = savedThinking
        }
        var checks: [String: Bool] = [:]
        var storageStatus: Int?
        do {
            switch scenario {
            case "v17performance":
                checks = try await checkUpdateOptimizations()
            case "v15search":
                setWritingMode(false)
                newConversation()
                selectProvider(AIProvider.deepSeek.id)
                preferences.webSearch = true
                deepThinking = false
                checks["deepSeekSearchEnabled"] = searchEnabled
                checks["searchSendAccepted"] = send("请联网查找苹果官方 Apple Watch Series 11 的尺寸，简短回答并引用来源。")
                try await awaitReply()
                checks["deepSeekAnswerComplete"] = current.messages.last?.state == .complete && current.messages.last?.providerName == "DeepSeek"
                checks["realSourcesAttached"] = !(current.messages.last?.sources ?? []).isEmpty
                checks["searchNoticeCleared"] = current.messages.last?.notice == nil
            case "v16siri":
                draft = "Siri 不应修改这份未发送草稿"
                let preservedID = currentID, preservedDraft = draft
                let preservedPreferences = preferences
                let ask = AskWristChatIntent()
                ask.question = "请用一句话回答：1加1等于多少？"
                let answer = try await ask.perform()
                checks["testSiriAskReturnsAnswerAndDialogWithoutForeground"] = !(answer.value ?? "").isEmpty && (answer as? IntentResultContainer<String, Never, Never, IntentDialog>)?.dialog != nil && AskWristChatIntent.supportedModes == .background && !AskWristChatIntent.openAppWhenRun
                checks["testSiriPreservesForegroundConversationDraftAndPreferences"] = currentID == preservedID && draft == preservedDraft && preferences == preservedPreferences && !isGenerating
                let siriID = UserDefaults.standard.string(forKey: "lastSiriConversationID")
                let followup = ContinueWristChatIntent(); followup.question = "把你刚才的答案改成英文。"
                let continued = try await followup.perform()
                checks["testSiriContinueReturnsDirectAnswerWithSameHistory"] = !(continued.value ?? "").isEmpty && (continued as? IntentResultContainer<String, Never, Never, IntentDialog>)?.dialog != nil && ContinueWristChatIntent.supportedModes == .background && UserDefaults.standard.string(forKey: "lastSiriConversationID") == siriID && conversations.first(where: { $0.id.uuidString == siriID })?.messages.count == 4
                let writer = WriteWithWristChatIntent()
                writer.assignment = "以那盏灯为题写一篇约800字的初三作文，写晚自习后父亲在校门口等我，语言有文学性，最后三段写感悟与立意。"
                let essay = try await writer.perform()
                let writingID = UserDefaults.standard.string(forKey: "lastSiriConversationID")
                let writingReply = conversations.first(where: { $0.id.uuidString == writingID })?.messages.last
                checks["testSiriWritingReturnsEssayWithoutChangingWorkspace"] = !(essay.value ?? "").isEmpty && (essay as? IntentResultContainer<String, Never, Never, IntentDialog>)?.dialog != nil && WriteWithWristChatIntent.supportedModes == .background && writingReply?.isEssay == true && writingReply?.state == .complete && preferences == preservedPreferences && currentID == preservedID && draft == preservedDraft
                await flushHistory()
                let disk = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: URL.applicationSupportDirectory.appendingPathComponent("WristChat/conversations.json")))
                checks["testSiriAnswerSavedForLaterWithoutSelectingIt"] = disk.contains(where: { $0.id.uuidString == writingID && $0.messages.last?.text == writingReply?.text }) && currentID == preservedID
            case "v14preview":
                preferences.silent = false
                seedWritingPreview()
                checks["writingWorkspaceVisible"] = preferences.essayMode && current.isWriting
            case "v14sources":
                setWritingMode(false); preferences.silent = false
                seedSourcePreview(staticPage: true)
                checks["sourceFixtureReady"] = current.messages.last?.sources?.count == 3
            case "v14workspace":
                setWritingMode(false)
                let chatID = currentID, chatDraft = draft
                draft = "未发送的聊天验收草稿"
                seedWritingPreview()
                checks["workspaceHasSeparateConversation"] = currentID != chatID && current.isWriting
                selectProvider(AIProvider.deepSeek.id)
                await refreshModels()
                deepThinking = false
                let original = essayVersions.last!
                draft = "另外一份未发送的作文草稿"
                checks["revisionAccepted"] = reviseEssay(original.id, action: .ending, target: 800, direction: "保留灯与父亲的细节，结尾三段依次写感悟、主旨、点题。")
                let writingID = currentID
                setWritingMode(false)
                checks["workspaceLockedDuringGeneration"] = currentID == writingID && preferences.essayMode
                try await awaitReply()
                checks["revisionComplete"] = current.messages.last?.state == .complete
                checks["targetRecorded"] = current.messages.last?.essayTarget == 800
                checks["actualCountNearTarget"] = current.messages.last.map { abs(EssayDocument($0.text).wordCount - 800) <= 80 } ?? false
                checks["originalRetained"] = essayVersions.first(where: { $0.id == original.id })?.text == original.text
                checks["twoVersions"] = essayVersions.count == 2
                checks["revisionPreservesDraft"] = draft == "另外一份未发送的作文草稿"
                setWritingMode(false)
                checks["chatDraftRestored"] = currentID == chatID && draft == "未发送的聊天验收草稿"
                draft = chatDraft
                setWritingMode(true)
                checks["workspaceRestored"] = currentID == writingID && essayVersions.count == 2
            case "v13providers":
                preferences = .init(); preferences.answerLength = .medium
                deepThinking = false
                let mimoKey = try Credentials.read(provider: .mimo)
                let deepKey = try Credentials.read(provider: .deepSeek)
                checks["separateKeychainCredentials"] = !mimoKey.isEmpty && !deepKey.isEmpty && mimoKey != deepKey
                newConversation()
                selectProvider(AIProvider.mimo.id)
                await refreshModels()
                selectedModelID = "mimo-v2.6-flash"
                checks["mimoSendAccepted"] = send("记住：我的验收颜色是橙色。只回答收到。")
                selectProvider(AIProvider.deepSeek.id)
                checks["providerLockedDuringGeneration"] = activeProviderID == AIProvider.mimo.id
                try await awaitReply()
                checks["mimoComplete"] = current.messages.last?.state == .complete
                selectProvider(AIProvider.deepSeek.id)
                await refreshModels()
                selectedModelID = "deepseek-flash"
                preferences.webSearch = true
                checks["unsupportedSearchVisiblyDisabled"] = !searchEnabled
                checks["deepSeekSendAccepted"] = send("我刚才说的验收颜色是什么？只回答颜色。")
                try await awaitReply()
                checks["crossProviderContextRetained"] = current.messages.last?.text.contains("橙") == true
                checks["deepSeekComplete"] = current.messages.last?.state == .complete
                checks["providerRecordedInHistory"] = current.messages.last?.providerName == "DeepSeek"
                let custom = AIProvider(id: "acceptance-openai", name: "兼容接口验证", baseURL: "https://api.deepseek.com/v1/", manualModelIDs: ["deepseek-flash"])
                try configureProvider(custom, key: deepKey)
                await refreshModels()
                selectedModelID = "deepseek-flash"
                checks["customProviderSendAccepted"] = send("只回复：兼容接口已连接。")
                try await awaitReply()
                checks["customProviderReplyComplete"] = current.messages.last?.state == .complete && current.messages.last?.text.contains("已连接") == true
                preferences.essayMode = true; preferences.answerLength = .medium
                await flushHistory()
                let restored = ChatStore()
                checks["providerSurvivesRestart"] = restored.activeProviderID == custom.id && restored.providers.contains { $0.id == custom.id }
                checks["mediumAndEssaySurviveRestart"] = restored.preferences.answerLength == .medium && restored.preferences.essayMode
                selectProvider(AIProvider.deepSeek.id)
            case "v13sources":
                newConversation()
                seedSourcePreview()
                checks["sourcesFixturePresent"] = current.messages.last?.sources?.count == 3
            case "features":
                let original = preferences
                preferences.answerLength = .long
                preferences.webSearch = true
                preferences.silent = true
                preferences.textSize = .large
                preferences.contextDepth = .recent
                preferences.language = .automatic
                preferences.allowsCellular = false
                preferences.customInstruction = "少用术语"
                save(); await flushHistory()
                let restored = ChatStore()
                await restored.flushHistory()
                checks["preferencesSurviveRestart"] = restored.preferences == preferences
                checks["silentSuppressesNotifications"] = !restored.preferences.shouldNotify
                let context = ChatContext.messages(history: [], prompt: "测试", preferences: restored.preferences)
                checks["searchAndLongAnswerInstructions"] = context[0].content.contains("已提供联网搜索工具") && context[0].content.contains("详细解释")
                checks["historyHasNoSeconds"] = HistoryTime.label(for: .now.addingTimeInterval(-125)) == "2分钟前"
                seedFeaturePreview()
                checks["tableBlockDetected"] = ReplyDocument.parse(current.messages.last?.text ?? "").contains {
                    if case .table(let table) = $0 { return table.headers.count == 3 && table.rows.count == 2 }
                    return false
                }
                preferences = original
            case "empty":
                newConversation()
                selectedModelID = "mimo-v2.6-flash"
                checks["emptyConversation"] = current.messages.isEmpty
            case "conversation":
                newConversation()
                selectedModelID = "mimo-v2.6-flash"
                checks["firstSendAccepted"] = send("记住：我喜欢橙色。只回答收到。")
                try await awaitReply()
                checks["firstReplyComplete"] = current.messages.last?.state == .complete
                selectedModelID = "mimo-v2.5"
                checks["secondSendAccepted"] = send("我喜欢什么颜色？只回答颜色。")
                try await awaitReply()
                checks["switchedModel"] = current.messages.last?.modelID == "mimo-v2.5"
                checks["contextRetained"] = current.messages.last?.text.contains("橙") == true
                checks["secondReplyComplete"] = current.messages.last?.state == .complete
            case "cancelRetry":
                newConversation()
                selectedModelID = "mimo-v2.6-flash"
                checks["sendAccepted"] = send("请列出20种常见水果，每种用一句话介绍口味。")
                let deadline = Date.now.addingTimeInterval(90)
                while isGenerating && current.messages.last?.text.isEmpty == true && Date.now < deadline {
                    try await Task.sleep(for: .milliseconds(40))
                }
                stop()
                checks["cancelled"] = current.messages.last?.state == .cancelled && !isGenerating
                checks["partialPreserved"] = current.messages.last?.text.isEmpty == false
                let previousText = current.messages.last?.text
                retry()
                try await awaitReply()
                checks["retryComplete"] = current.messages.last?.state == .complete
                checks["singleQuestionAfterRetry"] = current.messages.filter { $0.role == .user }.count == 1
                checks["previousReplyPreservedAfterRetry"] = current.messages.last?.previousReplies?.last?.text == previousText
            case "restore":
                checks["historyRestored"] = !histories.isEmpty
                checks["currentConversationRestored"] = !current.messages.isEmpty
                checks["noGeneratingMessageAfterRestore"] = !current.messages.contains { $0.state == .generating }
                checks["keychainRestored"] = hasKey
            case "drafts":
                guard let other = histories.first(where: { $0.id != currentID }) else {
                    checks["anotherConversationAvailable"] = false
                    break
                }
                let originalID = currentID
                let originalDraft = draft
                openConversation(other.id)
                let otherDraft = draft
                draft = "验收草稿乙"
                openConversation(originalID)
                draft = "验收草稿甲"
                await flushHistory()
                let coldLaunch = ChatStore()
                await coldLaunch.flushHistory()
                checks["draftSurvivesColdLaunch"] = coldLaunch.draft == "验收草稿甲"
                openConversation(other.id)
                checks["otherDraftRestored"] = draft == "验收草稿乙"
                draft = otherDraft
                openConversation(originalID)
                checks["originalDraftRestored"] = draft == "验收草稿甲"
                draft = originalDraft
                checks["currentModelFirst"] = orderedModels.first?.id == selectedModelID
                newConversation()
                let draftOnlyID = currentID
                draft = "未发送的验收草稿"
                await flushHistory()
                let draftOnlyReload = ChatStore()
                await draftOnlyReload.flushHistory()
                checks["unsentDraftSurvivesColdLaunch"] = draftOnlyReload.currentID == draftOnlyID &&
                    draftOnlyReload.draft == "未发送的验收草稿"
                checks["unsentDraftAppearsInHistory"] = histories.contains { $0.id == draftOnlyID }
                newConversation()
                checks["newConversationFromUnsentDraft"] = currentID != draftOnlyID && draft.isEmpty &&
                    histories.contains { $0.id == draftOnlyID }
                openConversation(originalID)
                newConversation()
                checks["newConversationPreservesUnsentDraft"] = histories.contains { $0.id == draftOnlyID }
                openConversation(draftOnlyID)
                checks["unsentDraftCanBeReopened"] = draft == "未发送的验收草稿"
                deleteConversation(draftOnlyID)
                openConversation(originalID)
                draft = originalDraft
            default: return
            }
        } catch {
            if case Credentials.CredentialError.storage(let status) = error { storageStatus = Int(status) }
            checks["timedOutOrInterrupted"] = false
        }
        save()
        await flushHistory()
        var report: [String: Any] = ["scenario": scenario, "checks": checks,
            "passed": !checks.isEmpty && checks.values.allSatisfy { $0 },
            "model": selectedModelID, "messages": current.messages.count]
        if let storageStatus { report["storageOSStatus"] = storageStatus }
        let directory = URL.applicationSupportDirectory.appendingPathComponent("WristChat")
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: directory.appendingPathComponent("acceptance-\(scenario).json"), options: .atomic)
    }

    private func awaitReply() async throws {
        let deadline = Date.now.addingTimeInterval(100)
        while isGenerating {
            if Date.now > deadline { stop(); throw MiMoError.disconnected }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
#endif
