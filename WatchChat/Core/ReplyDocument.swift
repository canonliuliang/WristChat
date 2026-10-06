// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

public struct ReplyTable: Equatable, Sendable {
    public var headers: [String]
    public var rows: [[String]]
}

public enum ReplyBlock: Equatable, Sendable {
    case text(String), code(String), table(ReplyTable)
}

public enum ReplyDocument {
    /// Small, linear Markdown block parser. Ordinary pipes and fenced code stay literal.
    public static func parse(_ markdown: String) -> [ReplyBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var blocks: [ReplyBlock] = []
        var text: [String] = []
        var index = 0
        func flushText() {
            let value = text.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !value.isEmpty { blocks.append(.text(value)) }
            text.removeAll(keepingCapacity: true)
        }
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushText()
                let fence = String(trimmed.prefix(3))
                index += 1
                var code: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index]); index += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                if index < lines.count { index += 1 }
                continue
            }
            if index + 1 < lines.count, let headers = cells(line),
               let separators = cells(lines[index + 1]), headers.count == separators.count,
               separators.allSatisfy(isSeparator) {
                flushText()
                var table = ReplyTable(headers: headers, rows: [])
                index += 2
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                      let row = cells(lines[index]) {
                    table.rows.append(row); index += 1
                }
                // Keep every value, including malformed extra columns; pad missing cells.
                let width = max(headers.count, table.rows.map(\.count).max() ?? 0)
                table.headers += Array(repeating: "", count: width - headers.count)
                table.rows = table.rows.map { $0 + Array(repeating: "", count: width - $0.count) }
                blocks.append(.table(table))
                continue
            }
            text.append(line); index += 1
        }
        flushText()
        return blocks
    }

    private static func isSeparator(_ cell: String) -> Bool {
        let value = cell.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return value.count >= 3 && value.allSatisfy { $0 == "-" }
    }

    private static func cells(_ line: String) -> [String]? {
        let line = line.trimmingCharacters(in: .whitespaces)
        var result: [String] = [], cell = ""
        var escaped = false, codeFence = 0, hasDelimiter = false
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let char = characters[index]
            if escaped {
                if char != "|" { cell.append("\\") }
                cell.append(char); escaped = false
            } else if char == "\\" { escaped = true }
            else if char == "`" {
                var count = 1
                while index + count < characters.count && characters[index + count] == "`" { count += 1 }
                if codeFence == 0 { codeFence = count }
                else if codeFence == count { codeFence = 0 }
                cell += String(repeating: "`", count: count)
                index += count - 1
            }
            else if char == "|" && codeFence == 0 { result.append(cell); cell = ""; hasDelimiter = true }
            else { cell.append(char) }
            index += 1
        }
        if escaped { cell.append("\\") }
        result.append(cell)
        guard hasDelimiter else { return nil }
        if line.hasPrefix("|") { result.removeFirst() }
        if line.hasSuffix("|"), result.last?.isEmpty == true { result.removeLast() }
        guard !result.isEmpty else { return nil }
        return result.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
