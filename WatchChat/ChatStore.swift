// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation
import Combine
import WatchKit

@MainActor
final class ChatStore: ObservableObject {
    static let shared = ChatStore()
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var currentID = UUID()
    @Published private(set) var isGenerating = false
    @Published private(set) var isThinking = false
    @Published private(set) var hasKey = false
    @Published private(set) var models = MiMoModel.defaults
    @Published private(set) var isRefreshingModels = false
    @Published var modelError: String?
    @Published var storageError: String?
    @Published private(set) var providers: [AIProvider]
    @Published private(set) var activeProviderID: String
    @Published var selectedModelID: String {
        didSet {
            let key = "selectedModelID.\(activeProviderID)"
            if defaults.string(forKey: key) != selectedModelID { defaults.set(selectedModelID, forKey: key) }
        }
    }
    @Published var deepThinking: Bool {
        didSet { if deepThinking != oldValue { defaults.set(deepThinking, forKey: "deepThinking") } }
    }
    @Published var preferences: ChatPreferences {
        didSet {
            guard preferences != oldValue else { return }
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences.v1") }
        }
    }
    @Published var siriPreferences: SiriPreferences {
        didSet {
            guard siriPreferences != oldValue else { return }
            if let data = try? JSONEncoder().encode(siriPreferences) { defaults.set(data, forKey: "siri.preferences.v1") }
        }
    }
    @Published var draft = "" {
        didSet {
            let key = draftKey(currentID)
            if defaults.string(forKey: key) != draft { defaults.set(draft, forKey: key) }
        }
    }

    private let client = MiMoClient()
    private let essayCache = EssayDocumentCache()
    private let defaults = UserDefaults.standard
    private var replyTask: Task<Void, Never>?
    private var generationID: UUID?
    private var replyID: UUID?
    private let historyURL: URL
    private let historyWriter: HistoryWriter
    private var historyLoadFailed = false
    private var pendingReplyText = ""
    private var modelRefreshID: UUID?
    private var isAnsweringSiri = false
    #if DEBUG
    var acceptanceHasRun = false
    #endif

    var current: Conversation { conversations.first(where: { $0.id == currentID }) ?? Conversation(id: currentID) }
    var activeProvider: AIProvider { providers.first { $0.id == activeProviderID } ?? .mimo }
    var selectedModel: MiMoModel { models.first { $0.id == selectedModelID } ?? MiMoModel(id: selectedModelID) }
    var canSearch: Bool { activeProvider.supportsSearch || activeProvider.apiProtocol == .deepSeek }
    var searchEnabled: Bool { canSearch && preferences.webSearch }
    func essayDocument(_ message: ChatMessage) -> EssayDocument { essayCache.document(id: message.id, text: message.text) }

    func answerSiri(question: String, writing: Bool = false, continuing: Bool = false,
                    conversationMode: SiriConversationMode = .fresh,
                    progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> SiriReply {
        guard !isAnsweringSiri else { throw SiriReplyError.busy }
        let plan = try SiriConversationPlan(question: question, writing: writing)
        let previousID = defaults.string(forKey: "lastSiriConversationID").flatMap(UUID.init(uuidString:))
        let previous = try plan.previousConversation(conversations.first(where: { $0.id == previousID }),
            mode: continuing ? .continuing : conversationMode, preferences: siriPreferences)
        let provider = activeProvider, model = selectedModelID
        let plannedOptions = siriPreferences.requestOptions(app: preferences, thinking: deepThinking, plan: plan)
        var options = plannedOptions.preferences
        if let previous { options.essayMode = previous.isWriting }
        if plan.webSearch == true && !canSearch { throw SiriReplyError.unsupportedSearch }
        let target = plan.writing ? 800 : nil
        let request = try SiriReplyRequest(question: plan.question, provider: provider, model: model,
            key: Credentials.read(provider: provider),
            searchKey: options.webSearch && provider.apiProtocol == .deepSeek ? Credentials.read(provider: .mimo) : "",
            preferences: options, thinking: plannedOptions.thinking, history: previous?.messages ?? [], essayTarget: target)
        isAnsweringSiri = true
        defer { isAnsweringSiri = false }
        let reply = try await SiriReplyService(client: client).answer(request, progress: progress)
        try Task.checkCancellation()
        var conversation = previous ?? Conversation(writingWorkspace: plan.writing)
        conversation.messages.append(ChatMessage(role: .user, text: request.question))
        conversation.messages.append(ChatMessage(role: .assistant, text: reply.text, modelID: model,
            state: reply.state, notice: reply.notice, sources: reply.sources, providerName: provider.name,
            isEssay: plan.writing || (previous != nil && conversation.isWriting), essayTarget: target))
        conversation.updatedAt = .now
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) { conversations[index] = conversation }
        else { conversations.append(conversation) }
        defaults.set(conversation.id.uuidString, forKey: "lastSiriConversationID")
        // Saving a Siri conversation doesn't select it or replace the current draft.
        save()
        await flushHistory()
        return reply
    }
    var essayVersions: [ChatMessage] {
        guard current.isWriting else { return [] }
        return current.messages.filter { $0.role == .assistant && !$0.text.isEmpty && $0.isEssay != false }
    }
    var writingMaterial: String {
        get { defaults.string(forKey: "writingMaterial.\(currentID)") ?? "" }
        set {
            let value = String(newValue.prefix(1800))
            guard value != writingMaterial else { return }
            objectWillChange.send()
            defaults.set(value, forKey: "writingMaterial.\(currentID)")
        }
    }
    var writingTarget: Int {
        get { let n = defaults.integer(forKey: "writingTarget.\(currentID)"); return n == 0 ? 800 : n }
        set {
            let value = min(2400, max(100, newValue))
            guard value != writingTarget else { return }
            objectWillChange.send()
            defaults.set(value, forKey: "writingTarget.\(currentID)")
        }
    }
    var histories: [Conversation] {
        conversations.filter { !$0.messages.isEmpty || hasDraft($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func hasDraft(_ id: UUID) -> Bool {
        !savedDraft(id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func historyTitle(_ conversation: Conversation) -> String {
        if !conversation.messages.isEmpty { return conversation.title }
        let text = savedDraft(conversation.id).replacingOccurrences(of: "\n", with: " ")
        return text.count > 24 ? String(text.prefix(24)) + "…" : text
    }

    var orderedModels: [MiMoModel] {
        let preferred = MiMoModel.preferred(in: models)
        return models.sorted {
            if $0.id == selectedModelID { return $1.id != selectedModelID }
            if $1.id == selectedModelID { return false }
            if $0.id == preferred { return $1.id != preferred }
            if $1.id == preferred { return false }
            return $0.id > $1.id
        }
    }

    init() {
        let defaults = UserDefaults.standard
        let savedProviders = defaults.data(forKey: "providers.v1")
            .flatMap { try? JSONDecoder().decode([AIProvider].self, from: $0) } ?? []
        let initialProviders: [AIProvider] = [.mimo, .deepSeek] + savedProviders.filter { !$0.isBuiltIn }
        providers = initialProviders
        let requested = defaults.string(forKey: "activeProviderID") ?? AIProvider.mimo.id
        let initialProviderID = initialProviders.contains { $0.id == requested } ? requested : AIProvider.mimo.id
        activeProviderID = initialProviderID
        let provider = initialProviders.first { $0.id == initialProviderID } ?? .mimo
        selectedModelID = defaults.string(forKey: "selectedModelID.\(initialProviderID)") ??
            (initialProviderID == AIProvider.mimo.id ? defaults.string(forKey: "selectedModelID") : nil) ?? provider.defaultModelID
        deepThinking = UserDefaults.standard.bool(forKey: "deepThinking")
        preferences = UserDefaults.standard.data(forKey: "preferences.v1")
            .flatMap { try? JSONDecoder().decode(ChatPreferences.self, from: $0) } ?? .init()
        siriPreferences = defaults.data(forKey: "siri.preferences.v1")
            .flatMap { try? JSONDecoder().decode(SiriPreferences.self, from: $0) } ?? .init()
        let directory = URL.applicationSupportDirectory.appendingPathComponent("WristChat", isDirectory: true)
        historyURL = directory.appendingPathComponent("conversations.json")
        historyWriter = HistoryWriter(url: historyURL)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: historyURL.path) {
                let data = try Data(contentsOf: historyURL)
                guard data.count <= 20_000_000 else { throw CocoaError(.fileReadTooLarge) }
                conversations = try JSONDecoder().decode([Conversation].self, from: data)
                for index in conversations.indices { conversations[index].recoverInterruptedResponses() }
            }
        } catch {
            historyLoadFailed = true
            storageError = "历史记录读取失败，原文件已保留。"
        }
        if let saved = defaults.string(forKey: "currentConversationID").flatMap(UUID.init(uuidString:)),
           conversations.contains(where: { $0.id == saved }) {
            currentID = saved
        } else if let latest = histories.first {
            currentID = latest.id
        } else {
            conversations.append(Conversation(id: currentID))
        }
        draft = defaults.string(forKey: draftKey(currentID)) ?? ""
        do { try Credentials.bootstrap() }
        catch { modelError = error.localizedDescription }
        do { hasKey = !(try Credentials.read(provider: provider)).isEmpty }
        catch { modelError = error.localizedDescription }
        loadModels(for: provider)
        // Reserve the current conversation before its first draft, including on a fresh install.
        save()
    }

    func refreshModels(force: Bool = true) async {
        guard !isRefreshingModels else { return }
        let provider = activeProvider
        let cache = "models.\(provider.id)"
        if !force, defaults.data(forKey: cache) != nil,
           let refreshed = defaults.object(forKey: "modelsRefreshedAt.\(provider.id)") as? Date,
           Date.now.timeIntervalSince(refreshed) < 21_600 { return }
        modelError = nil
        isRefreshingModels = true
        let refreshID = UUID(); modelRefreshID = refreshID
        defer { if modelRefreshID == refreshID { isRefreshingModels = false; modelRefreshID = nil } }
        do {
            let key = try Credentials.read(provider: provider)
            guard !key.isEmpty else { hasKey = false; throw MiMoError.missingKey }
            let available = try await client.models(key: key, allowsCellular: preferences.allowsCellular, provider: provider)
            guard activeProviderID == provider.id, modelRefreshID == refreshID else { return }
            models = available
            defaults.set(try JSONEncoder().encode(available), forKey: cache)
            defaults.set(Date.now, forKey: "modelsRefreshedAt.\(provider.id)")
            if !available.contains(where: { $0.id == selectedModelID }),
               let preferred = MiMoModel.preferred(in: available) { selectedModelID = preferred }
        } catch {
            if activeProviderID == provider.id, modelRefreshID == refreshID { modelError = Self.description(for: error) }
        }
    }

    func saveKey(_ key: String) throws {
        guard !isGenerating else { return }
        try Credentials.save(key, provider: activeProvider)
        hasKey = true
        defaults.removeObject(forKey: "modelsRefreshedAt.\(activeProviderID)")
        modelError = nil
    }

    func selectProvider(_ id: String) {
        guard !isGenerating, let provider = providers.first(where: { $0.id == id }), id != activeProviderID else { return }
        activeProviderID = id
        defaults.set(id, forKey: "activeProviderID")
        modelRefreshID = nil; isRefreshingModels = false; modelError = nil
        loadModels(for: provider)
        selectedModelID = defaults.string(forKey: "selectedModelID.\(id)") ?? provider.defaultModelID
        if !models.isEmpty, !models.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = MiMoModel.preferred(in: models) ?? provider.defaultModelID
        }
        hasKey = !((try? Credentials.read(provider: provider)) ?? "").isEmpty
        Task { await refreshModels(force: false) }
    }

    func configureProvider(_ provider: AIProvider, key: String) throws {
        guard !isGenerating else { return }
        guard !provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProviderError.invalidName }
        _ = try provider.endpoint("models")
        let old = providers.first { $0.id == provider.id }
        if key.isEmpty, old == nil || old?.baseURL != provider.baseURL { throw Credentials.CredentialError.format }
        if !key.isEmpty { try Credentials.save(key, provider: provider) }
        if let index = providers.firstIndex(where: { $0.id == provider.id }) { providers[index] = provider }
        else { providers.append(provider) }
        defaults.set(try JSONEncoder().encode(providers), forKey: "providers.v1")
        defaults.removeObject(forKey: "modelsRefreshedAt.\(provider.id)")
        defaults.removeObject(forKey: "models.\(provider.id)")
        if activeProviderID == provider.id {
            loadModels(for: provider)
            hasKey = !((try? Credentials.read(provider: provider)) ?? "").isEmpty
            if !models.contains(where: { $0.id == selectedModelID }) { selectedModelID = provider.defaultModelID }
            modelRefreshID = nil; isRefreshingModels = false
        } else { selectProvider(provider.id) }
        modelError = nil
    }

    private func loadModels(for provider: AIProvider) {
        let cached = defaults.data(forKey: "models.\(provider.id)") ??
            (provider.id == AIProvider.mimo.id ? defaults.data(forKey: "models") : nil)
        models = cached.flatMap { try? JSONDecoder().decode([MiMoModel].self, from: $0) } ?? provider.fallbackModels
    }

    func newConversation() {
        guard !isGenerating else { return }
        if current.messages.isEmpty && !hasDraft(currentID) { return }
        conversations.removeAll { $0.messages.isEmpty && !hasDraft($0.id) }
        currentID = UUID()
        conversations.append(Conversation(id: currentID, writingWorkspace: preferences.essayMode))
        draft = ""
        save()
    }

    func openConversation(_ id: UUID) {
        guard !isGenerating, conversations.contains(where: { $0.id == id }) else { return }
        currentID = id
        preferences.essayMode = current.isWriting
        draft = defaults.string(forKey: draftKey(id)) ?? ""
        save()
    }

    func setWritingMode(_ enabled: Bool) {
        guard !isGenerating else { return }
        if enabled {
            if !current.isWriting {
                defaults.set(currentID.uuidString, forKey: "lastChatConversationID")
                if let previous = histories.first(where: \.isWriting) { openConversation(previous.id) }
                else {
                    currentID = UUID()
                    conversations.append(Conversation(id: currentID, writingWorkspace: true))
                    draft = ""
                }
            }
        } else if current.isWriting {
            let saved = defaults.string(forKey: "lastChatConversationID").flatMap(UUID.init(uuidString:))
            let previous = conversations.first { $0.id == saved && !$0.isWriting } ?? histories.first { !$0.isWriting }
            if let previous { openConversation(previous.id) }
            else {
                currentID = UUID(); conversations.append(Conversation(id: currentID, writingWorkspace: false)); draft = ""
            }
        }
        preferences.essayMode = enabled
        save()
    }

    @discardableResult
    func sendEssay() -> Bool {
        let requirements = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requirements.isEmpty, requirements.count <= 1500 else { return false }
        let prompt = "作文生成任务。题目与要求：\(requirements)\n我的素材：\(writingMaterial.isEmpty ? "未提供；采用可信的初三生活事件，不声称是我的真实经历。" : writingMaterial)\n正文目标约\(writingTarget)个汉字，标题与标点不计。输出标题和完整正文，开头明确点题并引出下文，最后2–3段逐层写感悟、主旨与立意。"
        return send(prompt, essayTarget: writingTarget)
    }

    @discardableResult
    func reviseEssay(_ id: UUID, action: EssayRevision, target: Int, direction: String) -> Bool {
        guard !isGenerating, hasKey, let original = essayVersions.first(where: { $0.id == id }),
              original.state != .generating else { return false }
        let prompt = action.prompt(original: original.text,
            assignment: current.messages.first(where: { $0.role == .user })?.text ?? "保留原题",
            target: target, direction: direction)
        guard prompt.count <= 4000 else { modelError = "原稿太长，请先缩短素材再改稿。"; return false }
        preferences.essayMode = true
        mutateCurrent { $0.messages.append(ChatMessage(role: .user, text: prompt)) }
        // A revision must not discard a separate, unsent writing draft.
        generate(prompt: prompt, essayTarget: target)
        return true
    }

    func deleteConversation(_ id: UUID) {
        guard !isGenerating else { return }
        defaults.removeObject(forKey: draftKey(id))
        conversations.removeAll { $0.id == id }
        if id == currentID {
            currentID = histories.first?.id ?? UUID()
            if !conversations.contains(where: { $0.id == currentID }) {
                conversations.append(Conversation(id: currentID))
            }
            draft = defaults.string(forKey: draftKey(currentID)) ?? ""
        }
        save()
    }

    @discardableResult
    func send(_ rawPrompt: String, essayTarget: Int? = nil) -> Bool {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating, !prompt.isEmpty, prompt.count <= 4000 else { return false }
        guard hasKey else { modelError = MiMoError.missingKey.localizedDescription; return false }
        guard !selectedModelID.isEmpty else { modelError = ProviderError.invalidModel.localizedDescription; return false }
        if preferences.essayMode { mutateCurrent { $0.writingWorkspace = true } }
        mutateCurrent { $0.messages.append(ChatMessage(role: .user, text: prompt)) }
        draft = ""
        generate(prompt: prompt, essayTarget: essayTarget)
        return true
    }

    func retry() {
        guard !isGenerating, hasKey, let last = current.messages.last,
              last.role == .assistant, last.state != .complete,
              current.messages.dropLast().last?.role == .user else { return }
        let previous = (last.previousReplies ?? []) + [ReplyAttempt(message: last)]
        mutateCurrent { $0.messages.removeLast() }
        guard let prompt = current.messages.last, prompt.role == .user else { return }
        generate(prompt: prompt.text, previousReplies: previous, essayTarget: last.essayTarget)
    }

    private func generate(prompt: String, previousReplies: [ReplyAttempt]? = nil, essayTarget: Int? = nil) {
        let provider = activeProvider
        var options = preferences
        options.webSearch = searchEnabled
        let messages = ChatContext.messages(history: current.messages, prompt: prompt, preferences: options)
        let model = selectedModelID
        let thinking = deepThinking && provider.supportsThinking
        let response = ChatMessage(role: .assistant, text: "", modelID: model, state: .generating,
                                   previousReplies: previousReplies, providerName: provider.name, isEssay: options.essayMode, essayTarget: essayTarget)
        mutateCurrent { $0.messages.append(response) }
        let token = UUID()
        generationID = token
        replyID = response.id
        isGenerating = true
        isThinking = false
        pendingReplyText = ""
        save()
        replyTask = Task { [weak self] in
            guard let self else { return }
            var fullText = ""
            var finishedReason: String?
            var lastDisplay = Date.distantPast
            var lastSave = Date.now
            do {
                let key = try Credentials.read(provider: provider)
                let stream: AsyncThrowingStream<StreamEvent, Error>
                if options.webSearch && provider.apiProtocol == .deepSeek {
                    updateReply { $0.notice = "正在联网检索…" }
                    let searchKey = try Credentials.read(provider: .mimo)
                    stream = client.replyWithWebSearch(key: key, searchKey: searchKey, model: model,
                        messages: messages, query: prompt, thinking: thinking, preferences: options, provider: provider)
                } else {
                    stream = try client.reply(key: key, model: model, messages: messages, thinking: thinking,
                        preferences: options, provider: provider)
                }
                for try await event in stream {
                    try Task.checkCancellation()
                    guard generationID == token else { return }
                    switch event {
                    case .text(let delta):
                        fullText += delta
                        pendingReplyText = fullText
                        if isThinking { isThinking = false }
                        if Date.now.timeIntervalSince(lastDisplay) >= 0.18 {
                            updateReply { $0.text = fullText }
                            lastDisplay = .now
                        }
                    case .thinking:
                        if fullText.isEmpty && !isThinking { isThinking = true }
                    case .sources(let sources):
                        updateReply { message in
                            if message.notice == "正在联网检索…" { message.notice = nil }
                            var seen = Set((message.sources ?? []).map(\.id))
                            message.sources = (message.sources ?? []) + sources.filter { seen.insert($0.id).inserted }
                        }
                    case .searchFailed:
                        updateReply { $0.notice = "本次联网搜索失败，以下回答未核实实时信息。请检查联网服务插件。" }
                    case .finished(let reason): finishedReason = reason
                    case .done: break
                    }
                    if Date.now.timeIntervalSince(lastSave) >= 2 {
                        updateReply { $0.text = fullText }
                        save()
                        lastSave = .now
                    }
                }
                guard generationID == token else { return }
                updateReply { $0.text = fullText }
                guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MiMoError.emptyResponse
                }
                guard let reason = finishedReason else { throw MiMoError.disconnected }
                if reason == "stop", options.essayMode, let target = essayTarget,
                   EssaySizing.needsAdjustment(actual: EssayDocument(fullText).wordCount, target: target) {
                    let original = fullText
                    var adjusted = "", adjustedReason: String?
                    updateReply { $0.notice = "正在校准字数…" }
                    let correction = EssaySizing.prompt(text: original, target: target)
                    var correctionOptions = options
                    correctionOptions.webSearch = false
                    do {
                        let stream = try client.reply(key: key, model: model,
                            messages: ChatContext.messages(history: [], prompt: correction, preferences: correctionOptions),
                            thinking: thinking, preferences: correctionOptions, provider: provider)
                        for try await event in stream {
                            try Task.checkCancellation()
                            guard generationID == token else { return }
                            switch event {
                            case .text(let delta):
                                adjusted += delta
                                pendingReplyText = adjusted
                                if Date.now.timeIntervalSince(lastDisplay) >= 0.18 {
                                    updateReply { $0.text = adjusted }; lastDisplay = .now
                                }
                            case .finished(let value): adjustedReason = value
                            default: break
                            }
                        }
                        if adjustedReason == "stop", EssaySizing.preferRevision(original: EssayDocument(original).wordCount,
                            revised: EssayDocument(adjusted).wordCount, target: target) { fullText = adjusted }
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        // Keep the already completed first draft if calibration fails.
                    }
                    guard generationID == token else { return }
                    pendingReplyText = fullText
                    updateReply {
                        $0.text = fullText
                        $0.notice = EssaySizing.needsAdjustment(actual: EssayDocument(fullText).wordCount, target: target)
                            ? "目标约\(target)字，实际\(EssayDocument(fullText).wordCount)字，可继续调整。" : nil
                    }
                }
                updateReply {
                    if reason == "stop" { $0.state = .complete }
                    else if reason == "length" {
                        $0.state = .truncated
                        $0.notice = "已达到回复长度上限，可请 AI 简短回答后重试。"
                    } else {
                        $0.state = .interrupted
                        $0.notice = reason == "content_filter" ? "此回复被服务端过滤。" : "回复提前结束，可以重试。"
                    }
                }
                if preferences.shouldNotify { WKInterfaceDevice.current().play(.success) }
            } catch {
                guard generationID == token else { return }
                updateReply {
                    $0.text = fullText
                    $0.state = fullText.isEmpty ? .failed : .interrupted
                    $0.notice = Self.description(for: error)
                }
                if preferences.shouldNotify { WKInterfaceDevice.current().play(.failure) }
            }
            guard generationID == token else { return }
            isGenerating = false
            isThinking = false
            generationID = nil
            replyTask = nil
            save()
        }
    }

    func stop(background: Bool = false) {
        guard isGenerating else { return }
        generationID = nil
        replyTask?.cancel()
        replyTask = nil
        updateReply {
            $0.text = pendingReplyText
            $0.state = background ? .interrupted : .cancelled
            $0.notice = background ? "App 进入后台，回复已暂停。可以重试。" : "已停止生成。"
        }
        isGenerating = false
        isThinking = false
        save()
    }

    func save() {
        if defaults.string(forKey: "currentConversationID") != currentID.uuidString {
            defaults.set(currentID.uuidString, forKey: "currentConversationID")
        }
        // Never overwrite a file that couldn't be decoded at startup.
        guard !historyLoadFailed else { return }
        historyWriter.submit(conversations)
        Task { [weak self] in await self?.flushHistory() }
    }

    func flushHistory() async {
        guard !historyLoadFailed else { return }
        do { try await historyWriter.flush() }
        catch { storageError = "历史记录保存失败，请检查手表剩余空间。" }
    }

    #if DEBUG
    func checkUpdateOptimizations() async throws -> [String: Bool] {
        newConversation()
        mutateCurrent {
            $0.messages = [ChatMessage(role: .user, text: "性能验收"),
                           ChatMessage(role: .assistant, text: "第一段", state: .generating)]
        }
        let original = current
        let oldReplyID = replyID
        replyID = original.messages.last?.id
        defer { replyID = oldReplyID }
        var publications = 0
        let observation = $conversations.dropFirst().sink { _ in publications += 1 }
        for _ in 0..<20 {
            mutateCurrent { _ in }
            updateReply { $0.text = "第一段" }
        }
        var checks = ["testUnchangedReplyDoesNotPublishOrReorderHistory": publications == 0 && current == original]
        updateReply { $0.text += "，最后一段。"; $0.state = .cancelled }
        checks["testChangedReplyPublishesOnceAndRetainsFinalTextAndState"] = publications == 1
            && current.messages.last?.text == "第一段，最后一段。" && current.messages.last?.state == .cancelled
        observation.cancel()
        let options = preferences
        for length in AnswerLength.allCases {
            preferences.answerLength = length
            let saved = try JSONDecoder().decode(ChatPreferences.self, from: defaults.data(forKey: "preferences.v1")!)
            checks["testNativeLength\(length.rawValue.capitalized)PersistsWithoutChangingOtherOptions"] = saved.answerLength == length
                && { var expected = options; expected.answerLength = length; return saved == expected }()
        }
        preferences = options
        draft = "同一份未发送草稿"
        let firstID = currentID
        newConversation(); draft = "同一份未发送草稿"
        let secondID = currentID
        checks["testIdenticalDraftInSeparateConversationsPersistsBoth"] = firstID != secondID
            && defaults.string(forKey: draftKey(firstID)) == draft && defaults.string(forKey: draftKey(secondID)) == draft
        save(); await flushHistory()
        let saved = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: historyURL))
        checks["testChangedReplyAndSeparateDraftHistoryReachDisk"] = saved == conversations
            && saved.first(where: { $0.id == firstID })?.messages.last?.text == "第一段，最后一段。"
        return checks
    }

    func seedWritingPreview() {
        setWritingMode(true)
        let paragraph = "晚自习结束，校门口的灯把雨丝照得分明。父亲站在光里，手中的伞向我这边偏着。我看见他的袖口湿了一大片，便主动接过书包，把伞向他推了推。那盏灯照着我们并肩走过的路，也照见了我此前忽略的关怀。"
        mutateCurrent {
            $0.writingWorkspace = true
            $0.messages = [ChatMessage(role: .user, text: "以那盏灯为题写作文"),
                ChatMessage(role: .assistant, text: "那盏灯\n\n" + Array(repeating: paragraph, count: 8).joined(separator: "\n\n"), modelID: "deepseek-flash", isEssay: true)]
        }
        save()
    }

    func seedSourcePreview(staticPage: Bool = false) {
        seedFeaturePreview()
        mutateCurrent {
            $0.messages[$0.messages.count - 1].sources = [
                SearchSource(url: "https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos", title: "Apple Watch 设计指南", site: "Apple Developer")!,
                SearchSource(url: "https://api-docs.deepseek.com/", title: "DeepSeek API 文档", site: "DeepSeek")!,
                SearchSource(url: staticPage ? "https://example.com/" : "https://mimo.mi.com/", title: staticPage ? "网页打开测试" : "小米 MiMo", site: staticPage ? "Example Domain" : "小米 MiMo")!
            ]
        }
    }

    func seedFeaturePreview() {
        newConversation()
        mutateCurrent {
            $0.messages = [ChatMessage(role: .user, text: "比较短回答和长回答"),
                ChatMessage(role: .assistant, text: "可以按问题切换：\n\n| 模式 | 适合 | 表现 |\n| --- | --- | --- |\n| 短回答 | 日常快问 | 先给结论 |\n| 长回答 | 深入理解 | 步骤与例子 |\n\n在设置里选择，下一条提问生效。", modelID: "mimo-v2.6-flash")]
            $0.updatedAt = .now.addingTimeInterval(-120)
        }
        save()
    }
    #endif

    private func draftKey(_ id: UUID) -> String { "draft.\(id.uuidString)" }

    private func savedDraft(_ id: UUID) -> String {
        id == currentID ? draft : (defaults.string(forKey: draftKey(id)) ?? "")
    }

    private func mutateCurrent(_ action: (inout Conversation) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == currentID }) else { return }
        var updated = conversations[index]
        action(&updated)
        guard updated != conversations[index] else { return }
        updated.updatedAt = .now
        conversations[index] = updated
    }

    private func updateReply(_ action: (inout ChatMessage) -> Void) {
        mutateCurrent { conversation in
            guard let index = conversation.messages.firstIndex(where: { $0.id == replyID }) else { return }
            action(&conversation.messages[index])
        }
    }

    static func description(for error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "网络不可用，请检查手表的 Wi-Fi 或蜂窝连接。"
            case .timedOut: return "等待回复超时，可以重试或切换更快的模型。"
            case .cancelled: return "回复已停止。"
            default: return "无法连接 AI 提供商，请稍后重试。"
            }
        }
        if error is CancellationError { return "回复已停止。" }
        if error is MiMoError || error is Credentials.CredentialError || error is ProviderError { return error.localizedDescription }
        return "未能完成请求，请重试。"
    }
}
