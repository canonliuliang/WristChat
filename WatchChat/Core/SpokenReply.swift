// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

public enum SpokenReply {
    public static func text(from markdown: String) -> String {
        let blocks = ReplyDocument.parse(markdown).map { block in
            switch block {
            case .text(let text): return text
            case .code: return "代码部分请在屏幕查看。"
            case .table(let table):
                return table.rows.map { row in
                    zip(table.headers, row).map { "\($0)：\($1)" }.joined(separator: "，")
                }.joined(separator: "。\n")
            }
        }.joined(separator: "\n")
        return blocks
            .replacingOccurrences(of: #"!?\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
