// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import XCTest
@testable import WatchChatCore

final class ReplyDocumentTests: XCTestCase {
    func testTablesRetainTextHeadersRowsAndMultipleBlocks() {
        let result = ReplyDocument.parse("比较如下：\n\n| 方案 | 价格 |\n| :--- | ---: |\n| A | 10 |\n| B | 20 |\n\n备注。\n\n姓名 | 城市\n--- | ---\n小明 | 上海")
        XCTAssertEqual(result, [.text("比较如下："), .table(.init(headers: ["方案", "价格"], rows: [["A", "10"], ["B", "20"]])),
            .text("备注。"), .table(.init(headers: ["姓名", "城市"], rows: [["小明", "上海"]]))])
    }

    func testEscapedPipesAndInlineCodeRemainWithinCells() {
        let result = ReplyDocument.parse("| 说明 | 内容 |\n| --- | --- |\n| 管道 | a\\|b |\n| 代码 | `a|b` |")
        XCTAssertEqual(result, [.table(.init(headers: ["说明", "内容"], rows: [["管道", "a|b"], ["代码", "`a|b`"]]))])
        XCTAssertEqual(ReplyDocument.parse("A | B\r\n--- | ---\r\nx | ``a`|b``"),
            [.table(.init(headers: ["A", "B"], rows: [["x", "``a`|b``"]]))])
    }

    func testFencedCodeAndOrdinaryPipesNeverBecomeTables() {
        XCTAssertEqual(ReplyDocument.parse("命令 a | b\n```sh\n| key | value |\n| --- | --- |\n```\n尾段"),
            [.text("命令 a | b"), .code("| key | value |\n| --- | --- |"), .text("尾段")])
        XCTAssertEqual(ReplyDocument.parse("~~~\na|b\n~~~"), [.code("a|b")])
    }

    func testMalformedRowsPadMissingCellsAndNeverLoseExtraValues() {
        XCTAssertEqual(ReplyDocument.parse("| A | B |\n| --- | --- |\n| one |\n| x | y | z |"),
            [.table(.init(headers: ["A", "B", ""], rows: [["one", "", ""], ["x", "y", "z"]]))])
    }

    func testIncompleteStreamAndInvalidSeparatorStayReadableAsText() {
        for value in ["| A | B |\n| --", "A | B\n-- | ---", "A | B\n---", "A | B\n--- | value"] {
            XCTAssertEqual(ReplyDocument.parse(value), [.text(value)])
        }
        XCTAssertEqual(ReplyDocument.parse("| A | B |\n| --- | --- |"), [.table(.init(headers: ["A", "B"], rows: []))])
        XCTAssertEqual(ReplyDocument.parse(""), [])
    }
}
