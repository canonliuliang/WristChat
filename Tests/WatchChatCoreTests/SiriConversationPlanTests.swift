// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation
import XCTest
@testable import WatchChatCore

final class SiriConversationPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func previous(age: TimeInterval = 0, state: MessageState = .complete) -> Conversation {
        Conversation(messages: [.init(role: .user, text: "为什么天空是蓝色？"),
                                .init(role: .assistant, text: "空气散射了光。", state: state)],
                     updatedAt: now.addingTimeInterval(-age))
    }

    func testNaturalFollowupReusesRecentSiriConversation() throws {
        let plan = try SiriConversationPlan(question: " 再详细一点 ")
        let conversation = previous(age: 120)
        XCTAssertEqual(plan.question, "再详细一点")
        XCTAssertEqual(plan.answerLength, .long)
        XCTAssertEqual(try plan.previousConversation(conversation, mode: .automatic, preferences: .init(), now: now), conversation)
    }
    func testAutomaticContextAcceptsExactTenMinuteBoundary() throws {
        let plan = try SiriConversationPlan(question: "为什么？"), conversation = previous(age: 600)
        XCTAssertEqual(try plan.previousConversation(conversation, mode: .automatic, preferences: .init(), now: now), conversation)
    }
    func testAutomaticContextRejectsExpiredConversation() throws {
        let plan = try SiriConversationPlan(question: "为什么？")
        XCTAssertNil(try plan.previousConversation(previous(age: 601), mode: .automatic, preferences: .init(), now: now))
    }
    func testAutomaticContextRejectsFutureTimestamp() throws {
        let plan = try SiriConversationPlan(question: "为什么？")
        XCTAssertNil(try plan.previousConversation(previous(age: -1), mode: .automatic, preferences: .init(), now: now))
    }
    func testAutomaticContextRejectsMissingAndIncompleteReply() throws {
        let plan = try SiriConversationPlan(question: "再说说")
        XCTAssertNil(try plan.previousConversation(nil, mode: .automatic, preferences: .init(), now: now))
        for state in [MessageState.interrupted, .truncated, .failed, .cancelled, .generating] {
            XCTAssertNil(try plan.previousConversation(previous(state: state), mode: .automatic, preferences: .init(), now: now), "\(state)")
        }
        var unfinished = previous(); unfinished.messages.removeLast()
        XCTAssertNil(try plan.previousConversation(unfinished, mode: .automatic, preferences: .init(), now: now))
    }
    func testDisabledAutomaticContextAndLegacyFreshRemainIndependent() throws {
        var settings = SiriPreferences(); settings.automaticallyContinues = false
        let plan = try SiriConversationPlan(question: "再说说"), conversation = previous()
        XCTAssertNil(try plan.previousConversation(conversation, mode: .automatic, preferences: settings, now: now))
        XCTAssertNil(try plan.previousConversation(conversation, mode: .fresh, preferences: .init(), now: now))
    }
    func testExplicitContinuationKeepsOlderConversationAndReportsMissingHistory() throws {
        var settings = SiriPreferences(); settings.automaticallyContinues = false
        let plan = try SiriConversationPlan(question: "继续解释"), conversation = previous(age: 3600)
        XCTAssertEqual(try plan.previousConversation(conversation, mode: .continuing, preferences: settings, now: now), conversation)
        XCTAssertThrowsError(try plan.previousConversation(nil, mode: .continuing, preferences: settings, now: now)) {
            XCTAssertEqual($0 as? SiriReplyError, .noPreviousConversation)
        }
    }
    func testNewTopicStripsControlAndNeverReusesPreviousHistory() throws {
        let plan = try SiriConversationPlan(question: "换个话题，为什么天空是蓝色？")
        XCTAssertEqual(plan.question, "为什么天空是蓝色？")
        XCTAssertTrue(plan.startsNewConversation)
        for mode in [SiriConversationMode.automatic, .continuing, .fresh] {
            XCTAssertNil(try plan.previousConversation(previous(), mode: mode, preferences: .init(), now: now))
        }
    }
    func testQuestionsAboutControlPhrasesAreNotSilentlyChanged() throws {
        let plan = try SiriConversationPlan(question: "换个话题是什么意思？")
        XCTAssertEqual(plan.question, "换个话题是什么意思？")
        XCTAssertFalse(plan.startsNewConversation)
        XCTAssertNil(plan.answerLength); XCTAssertNil(plan.webSearch)
    }
    func testSpokenOverridesAffectRequestWithoutMutatingAppSettings() throws {
        var app = ChatPreferences(); app.answerLength = .medium; app.webSearch = false
        app.customInstruction = "回答用中文"; app.silent = true
        let original = app
        let plan = try SiriConversationPlan(question: "详细回答，联网回答，今天长沙天气怎样？")
        let result = SiriPreferences().requestOptions(app: app, thinking: true, plan: plan)
        XCTAssertEqual(plan.question, "今天长沙天气怎样？")
        XCTAssertEqual(result.preferences.answerLength, .long)
        XCTAssertTrue(result.preferences.webSearch); XCTAssertFalse(result.thinking)
        var expected = original; expected.answerLength = .long; expected.webSearch = true
        XCTAssertEqual(result.preferences, expected)
        XCTAssertEqual(app, original)
    }
    func testSpokenNoSearchAndShorterFollowup() throws {
        var app = ChatPreferences(); app.webSearch = true; app.answerLength = .long
        let offline = try SiriConversationPlan(question: "不要联网，解释光合作用")
        XCTAssertEqual(offline.question, "解释光合作用")
        XCTAssertFalse(SiriPreferences().requestOptions(app: app, thinking: true, plan: offline).preferences.webSearch)
        let shorter = try SiriConversationPlan(question: "再简短一点")
        XCTAssertEqual(shorter.question, "再简短一点"); XCTAssertEqual(shorter.answerLength, .short)
    }
    func testSiriResponseStylesPreserveOtherOptionsAndFollowAppThinking() throws {
        var app = ChatPreferences(); app.answerLength = .long; app.webSearch = true; app.silent = true
        let plan = try SiriConversationPlan(question: "解释光合作用")
        for (style, length, thinking) in [(SiriResponseStyle.quick, AnswerLength.short, false), (.balanced, .medium, false), (.followApp, .long, true)] {
            var settings = SiriPreferences(); settings.responseStyle = style
            let result = settings.requestOptions(app: app, thinking: true, plan: plan)
            var expected = app; expected.answerLength = length
            XCTAssertEqual(result.preferences, expected, "\(style)")
            XCTAssertEqual(result.thinking, thinking, "\(style)")
        }
    }
    func testEssayRequestStartsSeparateWritingContextWithoutMistakingExplanations() throws {
        let plan = try SiriConversationPlan(question: "帮我写一篇以灯为题的作文，写父亲接我回家。")
        XCTAssertTrue(plan.writing)
        XCTAssertNil(try plan.previousConversation(previous(), mode: .automatic, preferences: .init(), now: now))
        XCTAssertTrue(SiriPreferences().requestOptions(app: .init(), thinking: false, plan: plan).preferences.essayMode)
        XCTAssertFalse(try SiriConversationPlan(question: "写一篇关于作文结构的说明").writing)
    }
    func testInputValidationRejectsEmptyOversizedAndEmptyControlRemainder() throws {
        XCTAssertEqual(try SiriQuestionText.validate(" \n1加1等于多少？ "), "1加1等于多少？")
        XCTAssertEqual(try SiriQuestionText.validate(String(repeating: "问", count: 4000)).count, 4000)
        for value in [" \n ", "换个话题，", "不要联网，", "详细回答："] {
            XCTAssertThrowsError(try SiriConversationPlan(question: value)) { XCTAssertEqual($0 as? SiriReplyError, .emptyQuestion) }
        }
        XCTAssertThrowsError(try SiriConversationPlan(question: String(repeating: "问", count: 4001))) {
            XCTAssertEqual($0 as? SiriReplyError, .questionTooLong)
        }
    }
    func testSiriPreferencesMigrationAndRoundTrip() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(SiriPreferences.self, from: Data("{}".utf8)), .init())
        let fallback = try decoder.decode(SiriPreferences.self, from: Data(#"{"responseStyle":"future","automaticallyContinues":false}"#.utf8))
        XCTAssertEqual(fallback.responseStyle, .quick); XCTAssertFalse(fallback.automaticallyContinues)
        let partlyMalformed = try decoder.decode(SiriPreferences.self, from: Data(#"{"responseStyle":"balanced","automaticallyContinues":"bad"}"#.utf8))
        XCTAssertEqual(partlyMalformed.responseStyle, .balanced); XCTAssertTrue(partlyMalformed.automaticallyContinues)
        var settings = SiriPreferences(); settings.responseStyle = .followApp; settings.automaticallyContinues = false
        XCTAssertEqual(try decoder.decode(SiriPreferences.self, from: JSONEncoder().encode(settings)), settings)
    }
}
