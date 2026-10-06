// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

/// A small, bounded cache avoids recounting every saved draft on UI-only updates.
public final class EssayDocumentCache: @unchecked Sendable {
    private struct Entry { let text: String; let document: EssayDocument }
    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []
    private var characters = 0

    public init() {}

    public func document(id: UUID, text: String) -> EssayDocument {
        lock.withLock {
            if let entry = entries[id], entry.text == text { return entry.document }
            let document = EssayDocument(text)
            if let old = entries.removeValue(forKey: id) { characters -= old.text.count }
            order.removeAll { $0 == id }
            // A single very large reply should not evict and then overfill the cache.
            guard text.count <= 64_000 else { return document }
            while entries.count >= 24 || characters + text.count > 64_000 {
                guard !order.isEmpty else { break }
                let oldest = order.removeFirst()
                if let old = entries.removeValue(forKey: oldest) { characters -= old.text.count }
            }
            entries[id] = Entry(text: text, document: document)
            order.append(id); characters += text.count
            return document
        }
    }
}
