// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import XCTest
@testable import WatchChatCore

final class WritingFeatureTests: XCTestCase {
    func testSilentModeDisablesReadAloudAndFeedback() {
        var preferences = ChatPreferences()
        XCTAssertTrue(preferences.canReadAloud)
        preferences.silent = true
        XCTAssertFalse(preferences.canReadAloud)
        XCTAssertFalse(preferences.shouldNotify)
        preferences.silent = false
        XCTAssertTrue(preferences.canReadAloud)
    }

    func testLengthSliderSnapsAndClampsThreePositions() {
        XCTAssertEqual(AnswerLength(sliderValue: -1), .short)
        XCTAssertEqual(AnswerLength(sliderValue: 0.49), .short)
        XCTAssertEqual(AnswerLength(sliderValue: 0.5), .medium)
        XCTAssertEqual(AnswerLength(sliderValue: 1.49), .medium)
        XCTAssertEqual(AnswerLength(sliderValue: 1.5), .long)
        XCTAssertEqual(AnswerLength(sliderValue: 8), .long)
        XCTAssertEqual(AnswerLength(sliderValue: .nan), .short)
        XCTAssertEqual(AnswerLength.allCases.map(\.sliderValue), [0, 1, 2])
    }

    func testActualBodyCountExcludesTitlePunctuationAndSpaces() {
        let article = EssayDocument("# **那盏灯**\n\n灯，还亮着。\n雨停了！ A12 🙂")
        XCTAssertEqual(article.title, "那盏灯")
        XCTAssertEqual(article.paragraphs.count, 2)
        XCTAssertEqual(article.wordCount, 10) // 7 Chinese characters + A12.
        XCTAssertFalse(article.body.contains("那盏灯"))
        XCTAssertEqual(EssayDocument("只有正文，没有标题。").wordCount, 8)
        XCTAssertEqual(EssayDocument("").wordCount, 0)
    }

    func testEveryRevisionSuppliesOriginalWithoutDependingOnContext() {
        let original = "那盏灯\n父亲递给我一把伞。\n我把它收好。"
        for action in EssayRevision.allCases {
            let prompt = action.prompt(original: original, assignment: "以灯为题", target: 800, direction: "保留父亲递伞")
            XCTAssertTrue(prompt.contains(original), action.title)
            XCTAssertTrue(prompt.contains("以灯为题"), action.title)
            XCTAssertTrue(prompt.contains("保留父亲递伞"), action.title)
            XCTAssertTrue(prompt.contains("约800个正文汉字"), action.title)
            XCTAssertTrue(prompt.contains("输出完整的新稿"), action.title)
            XCTAssertTrue(prompt.contains("保留未经要求修改的事实"), action.title)
            var preferences = ChatPreferences(); preferences.contextDepth = .none; preferences.essayMode = true
            let messages = ChatContext.messages(history: [], prompt: prompt, preferences: preferences)
            XCTAssertEqual(messages.last?.content, prompt)
        }
    }

    func testShorterLongerAndThemeRequestsHaveDistinctGoals() {
        XCTAssertEqual(EssayRevision.shorten.targetCount(for: 800), 600)
        XCTAssertEqual(EssayRevision.expand.targetCount(for: 800), 1000)
        XCTAssertEqual(EssayRevision.shorten.targetCount(for: 150), 100)
        XCTAssertEqual(EssayRevision.expand.targetCount(for: 2350), 2400)
        XCTAssertTrue(EssayRevision.theme.prompt(original: "旧稿", assignment: "灯", target: 800).contains("重新组织文章立意"))
        XCTAssertTrue(EssayRevision.ending.prompt(original: "旧稿", assignment: "灯", target: 800).contains("最后2–3段"))
    }

    func testEssayRulesUseExplicitOpeningAndLayeredFinalParagraphs() {
        let rules = EssayWriting.instruction
        for text in ["开门点题", "引出下文", "最后2–3段", "升华、感悟、主旨和立意", "较华丽", "前文事实支撑"] {
            XCTAssertTrue(rules.contains(text), text)
        }
        XCTAssertFalse(rules.contains("避免突然拔高、喊口号、总结全文"))
        XCTAssertTrue(rules.contains("不擅自编造用户的真实经历"))
        XCTAssertTrue(rules.contains("约800字"))
    }

    func testOldHistoriesDecodeAndExplicitChatModeWinsOverKeywords() throws {
        let old = #"{"id":"AEF931D3-0091-4046-8252-34505D44A91F","messages":[],"updatedAt":0}"#
        let conversation = try JSONDecoder().decode(Conversation.self, from: Data(old.utf8))
        XCTAssertNil(conversation.writingWorkspace)
        XCTAssertFalse(conversation.isWriting)
        let messages = [ChatMessage(role: .user, text: "写一篇作文")]
        XCTAssertTrue(Conversation(messages: messages).isWriting)
        XCTAssertFalse(Conversation(messages: messages, writingWorkspace: false).isWriting)
    }

    func testSizingRepairsLargeDeviationAndOnlyKeepsCloserCompleteDraft() {
        XCTAssertFalse(EssaySizing.needsAdjustment(actual: 793, target: 800))
        XCTAssertTrue(EssaySizing.needsAdjustment(actual: 683, target: 800))
        XCTAssertTrue(EssaySizing.needsAdjustment(actual: 971, target: 800))
        XCTAssertTrue(EssaySizing.preferRevision(original: 683, revised: 810, target: 800))
        XCTAssertFalse(EssaySizing.preferRevision(original: 793, revised: 900, target: 800))
        XCTAssertFalse(EssaySizing.preferRevision(original: 683, revised: 0, target: 800))
        let original = "那盏灯\n父亲的袖子湿了。"
        XCTAssertTrue(EssaySizing.prompt(text: original, target: 800).contains(original))
        XCTAssertTrue(EssaySizing.prompt(text: original, target: 800).contains("770至830字"))
    }
}
