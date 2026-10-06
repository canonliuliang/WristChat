// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation
import XCTest
@testable import WatchChatCore

final class ProviderFeatureTests: XCTestCase {
    func testProviderRequestsKeepEndpointsCredentialsAndParametersSeparate() throws {
        let client = MiMoClient()
        let messages = [APIMessage(role: "user", content: "解释一道数学题")]
        var prefs = ChatPreferences(); prefs.answerLength = .medium; prefs.allowsCellular = false
        let mimo = try client.replyRequest(key: "mimo-test-key", model: "mimo-v2.6-flash", messages: messages, thinking: false, preferences: prefs)
        let deep = try client.replyRequest(key: "deepseek-test-key", model: "deepseek-flash", messages: messages, thinking: true, preferences: prefs, provider: .deepSeek)
        let custom = AIProvider(name: "测试平台", baseURL: "https://example.com/v1/")
        let other = try client.replyRequest(key: "custom-test-key", model: "my-model", messages: messages, thinking: true, preferences: prefs, provider: custom)
        XCTAssertEqual(mimo.url?.absoluteString, "https://api.xiaomimimo.com/v1/chat/completions")
        XCTAssertEqual(mimo.value(forHTTPHeaderField: "api-key"), "mimo-test-key")
        XCTAssertNil(mimo.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(deep.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(deep.value(forHTTPHeaderField: "Authorization"), "Bearer deepseek-test-key")
        XCTAssertNil(deep.value(forHTTPHeaderField: "api-key"))
        XCTAssertEqual(other.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(other.value(forHTTPHeaderField: "Authorization"), "Bearer custom-test-key")
        XCTAssertFalse(deep.allowsCellularAccess)
        let mb = try body(mimo), db = try body(deep), cb = try body(other)
        XCTAssertEqual(mb["max_completion_tokens"] as? Int, 4096)
        XCTAssertNil(mb["max_tokens"])
        XCTAssertEqual(db["max_tokens"] as? Int, 16384)
        XCTAssertNil(db["max_completion_tokens"])
        XCTAssertEqual((db["thinking"] as? [String:String])?["type"], "enabled")
        XCTAssertNil(db["tools"])
        XCTAssertNil(cb["thinking"])
        XCTAssertNil(cb["tools"])
        XCTAssertEqual(cb["max_tokens"] as? Int, 4096)
    }

    func testUnsupportedSearchFailsBeforeBuildingRequest() throws {
        var prefs = ChatPreferences(); prefs.webSearch = true
        for provider in [AIProvider.deepSeek, AIProvider(name:"自定义",baseURL:"https://example.com/v1/")] {
            XCTAssertThrowsError(try MiMoClient().replyRequest(key: "test-key", model:"test-model", messages:[],thinking:false,preferences:prefs,provider:provider)) {
                XCTAssertEqual($0 as? ProviderError, .searchUnsupported)
            }
        }
    }

    func testProviderRejectsCredentialBearingOrInsecureURLs() throws {
        for url in ["http://example.com/v1", "https://key@example.com/v1", "https://example.com/v1?key=secret", "https://example.com/v1#key", "https://example.com/v1/chat/completions", "https://"] {
            XCTAssertThrowsError(try AIProvider(name:"测试",baseURL:url).endpoint("models")) {
                XCTAssertEqual($0 as? ProviderError,.invalidURL)
            }
        }
        XCTAssertEqual(try AIProvider(name:"测试",baseURL:"https://example.com/api/v1").endpoint("models").path,"/api/v1/models")
    }

    func testOldPreferencesAndHistorySurviveNewFields() throws {
        let old = Data(#"{"answerLength":"long","webSearch":true,"silent":true,"haptics":false,"contextDepth":"recent","language":"automatic","textSize":"large","allowsCellular":false,"showSources":false,"customInstruction":"少用术语"}"#.utf8)
        let prefs = try JSONDecoder().decode(ChatPreferences.self,from:old)
        XCTAssertEqual(prefs.answerLength,.long)
        XCTAssertTrue(prefs.webSearch); XCTAssertTrue(prefs.silent)
        XCTAssertEqual(prefs.contextDepth,.recent); XCTAssertEqual(prefs.customInstruction,"少用术语")
        XCTAssertFalse(prefs.allowsCellular); XCTAssertFalse(prefs.showSources)
        XCTAssertFalse(prefs.essayMode); XCTAssertEqual(prefs.speechRate,1)
        let oldMessage = Data(#"{"id":"AEF931D3-0091-4046-8252-34505D44A91F","role":"assistant","text":"旧回复","date":0,"modelID":"mimo-v2.5","state":"complete"}"#.utf8)
        let message = try JSONDecoder().decode(ChatMessage.self,from:oldMessage)
        XCTAssertEqual(message.text,"旧回复"); XCTAssertEqual(message.state,.complete)
        XCTAssertNil(message.providerName)
    }

    func testMediumAndEssayInstructionsRespectOptInAndTaskScope() throws {
        var prefs = ChatPreferences(); prefs.answerLength = .medium
        let normal = ChatContext.messages(history:[],prompt:"写一篇作文",preferences:prefs)[0].content
        XCTAssertTrue(normal.contains("300至500字")); XCTAssertFalse(normal.contains("长沙"))
        XCTAssertEqual(prefs.completionBudget(thinking:false),4096)
        prefs.essayMode = true; prefs.answerLength = .short
        let essay = ChatContext.messages(history:[],prompt:"以灯为题写作文",preferences:prefs)[0].content
        for rule in ["约800字","长沙中考","初三","普通问答不强行写成作文","作文规则优先于普通回答长度","审题切题 > 内容真实具体 > 中心立意 > 情感真挚 > 文学性 > 结构完整 > 语言表达 > 开头结尾","不擅自编造用户的真实经历","满篇金句","开头重点打磨","只要求改一段时不重写整篇"] {
            XCTAssertTrue(essay.contains(rule),rule)
        }
        XCTAssertEqual(prefs.completionBudget(thinking:false),8192)
        prefs.essayMode = false
        XCTAssertFalse(ChatContext.messages(history:[],prompt:"写一篇作文",preferences:prefs)[0].content.contains("【作文模式"))
    }

    func testLegacyModelsAndDescriptions() {
        let current = ["mimo-v2.6-flash","mimo-v2.6-pro","mimo-v2.6-pro-ultraspeed","deepseek-flash","deepseek-v4-pro"].map(MiMoModel.init)
        XCTAssertTrue(current.allSatisfy { !$0.isLegacy })
        XCTAssertTrue(["mimo-v2.5","mimo-v2.5-pro","mimo-v2.5-pro-ultraspeed","deepseek-chat"].map(MiMoModel.init).allSatisfy(\.isLegacy))
        XCTAssertTrue(MiMoModel(id:"mimo-v2.6-pro-ultraspeed").detail.contains("加速版本"))
        XCTAssertEqual(MiMoModel(id:"deepseek-flash",name:"DeepSeek-V4.1-Flash").title,"DeepSeek V4.1 Flash")
        XCTAssertEqual(MiMoModel(id:"custom-model").title,"custom-model")
    }

    func testSpeechDoesNotReadMarkdownCodeOrRawURLs() {
        let markdown = "# **结论**\n看[原文](https://example.com/private?q=1)。\n\n|模式|用途|\n|---|---|\n|短|快问|\n\n```swift\nlet secret = 42\n```"
        let spoken = SpokenReply.text(from:markdown)
        XCTAssertTrue(spoken.hasPrefix("结论\n看原文。"))
        XCTAssertTrue(spoken.contains("模式：短，用途：快问"))
        XCTAssertTrue(spoken.contains("代码部分请在屏幕查看。"))
        XCTAssertFalse(spoken.contains("https://")); XCTAssertFalse(spoken.contains("secret"))
        XCTAssertFalse(spoken.contains("**")); XCTAssertFalse(spoken.contains("|---|"))
    }

    private func body(_ request:URLRequest) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(request.httpBody)) as? [String:Any])
    }
}
