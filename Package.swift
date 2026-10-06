// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import PackageDescription

let package = Package(
    name: "WatchChatCore",
    platforms: [.macOS(.v15), .watchOS(.v11)],
    products: [.library(name: "WatchChatCore", targets: ["WatchChatCore"])],
    targets: [
        .target(name: "WatchChatCore", path: "WatchChat/Core"),
        .testTarget(name: "WatchChatCoreTests", dependencies: ["WatchChatCore"])
    ]
)
