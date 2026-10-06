// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

public enum WristChatRoute: String, CaseIterable, Sendable {
    case ask, history, settings

    public var url: URL { URL(string: "wristchat://\(rawValue)")! }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "wristchat",
              url.user == nil, url.password == nil, url.port == nil,
              url.path.isEmpty || url.path == "/",
              url.query == nil, url.fragment == nil,
              let host = url.host?.lowercased() else { return nil }
        self.init(rawValue: host)
    }

    public var title: String {
        switch self {
        case .ask: "提问"
        case .history: "历史"
        case .settings: "设置"
        }
    }

    public var symbol: String {
        switch self {
        case .ask: "square.and.pencil"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }
}
