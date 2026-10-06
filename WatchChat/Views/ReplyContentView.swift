// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct ReplyContentView: View, Equatable {
    let text: String
    @State private var blocks: [ReplyBlock] = []
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let value):
                    Text(Self.inline(value)).fixedSize(horizontal: false, vertical: true)
                case .code(let value):
                    ScrollView(.horizontal) {
                        Text(value).font(.system(.footnote, design: .monospaced)).fixedSize().padding(8)
                    }.background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 8))
                case .table(let table): ReplyTableView(table: table)
                }
            }
        }
        // Reparse only changed reply text, never on another message's streaming updates.
        .onChange(of: text, initial: true) { _, value in blocks = ReplyDocument.parse(value) }
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

private struct ReplyTableView: View {
    let table: ReplyTable
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("左右滑动查看表格", systemImage: "arrow.left.and.right")
                .font(.caption2).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { column in
                            cell(table.headers[column], column: column, header: true)
                        }
                    }.background(Color(white: 0.19))
                    ForEach(table.rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(table.headers.indices, id: \.self) { column in
                                cell(table.rows[row][column], column: column, header: false)
                            }
                        }.background(Color(white: row.isMultiple(of: 2) ? 0.07 : 0.12))
                    }
                }
            }.accessibilityLabel("表格，\(table.headers.count)列，\(table.rows.count)行")
        }
    }

    private func cell(_ value: String, column: Int, header: Bool) -> some View {
        Text(ReplyContentView.inline(value)).fontWeight(header ? .semibold : .regular)
            .fixedSize(horizontal: false, vertical: true).frame(width: 112, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .accessibilityLabel(header ? value : "\(table.headers[column])：\(value)")
    }
}
