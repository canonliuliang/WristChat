// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

/// Snapshots are encoded and atomically written off the UI thread, in order.
/// A busy writer coalesces pending snapshots instead of building a write backlog.
public final class HistoryWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.liuliang.WristChat.history", qos: .utility)
    private let lock = NSLock()
    private let url: URL
    private var pending: [Conversation]?
    private var running = false
    private var lastError: Error?
    // Accessed only on queue. Retain the last successful snapshot, not an encoded copy.
    private var lastWrittenSnapshot: [Conversation]?

    public init(url: URL) { self.url = url }

    public func submit(_ snapshot: [Conversation]) {
        let start = lock.withLock {
            pending = snapshot
            if running { return false }
            running = true
            return true
        }
        if start { queue.async { [self] in drain() } }
    }

    public func flush() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                let error = lock.withLock { lastError }
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func drain() {
        while true {
            let snapshot = lock.withLock { () -> [Conversation]? in
                guard let snapshot = pending else { running = false; return nil }
                pending = nil
                return snapshot
            }
            guard let snapshot else { return }
            if snapshot == lastWrittenSnapshot { continue }
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
                lastWrittenSnapshot = snapshot
                lock.withLock { lastError = nil }
            } catch {
                // A retry, even with unchanged content, must attempt the write again.
                lastWrittenSnapshot = nil
                lock.withLock { lastError = error }
            }
        }
    }
}
