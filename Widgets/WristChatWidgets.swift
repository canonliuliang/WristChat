// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI
import WidgetKit

struct WristChatEntry: TimelineEntry {
    let date: Date
}

struct WristChatProvider: TimelineProvider {
    func placeholder(in context: Context) -> WristChatEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (WristChatEntry) -> Void) {
        completion(.init(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WristChatEntry>) -> Void) {
        // These are shortcuts; no polling or network requests are needed.
        completion(Timeline(entries: [.init(date: .now)], policy: .never))
    }
}

struct WristChatAskView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("腕聊", systemImage: "text.bubble")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("腕聊").font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 7) {
                        Image(systemName: "text.bubble").font(.body)
                        Text("问一句").font(.headline)
                        Spacer(minLength: 0)
                    }
                    .widgetAccentable()
                }
            case .accessoryCorner:
                Image(systemName: "text.bubble")
                    .font(.title2).widgetAccentable()
                    .widgetLabel { Text("问腕聊") }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "text.bubble")
                        .font(.system(size: 24, weight: .medium)).widgetAccentable()
                }
            }
        }
        .containerBackground(Color.black, for: .widget)
        .widgetURL(WristChatRoute.ask.url)
        .accessibilityLabel("腕聊，打开提问")
    }
}

struct WristChatAskWidget: Widget {
    let kind = "WristChatAsk"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WristChatProvider()) { _ in WristChatAskView() }
            .configurationDisplayName("问腕聊")
            .description("从表盘或智能叠放直接进入提问。")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct WristChatActionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("腕聊").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                action(.ask)
                Divider().overlay(Color.white.opacity(0.12))
                action(.history)
                Divider().overlay(Color.white.opacity(0.12))
                action(.settings)
            }
        }
        .containerBackground(Color.black, for: .widget)
        .widgetURL(WristChatRoute.ask.url)
    }

    private func action(_ route: WristChatRoute) -> some View {
        Link(destination: route.url) {
            VStack(spacing: 3) {
                Image(systemName: route.symbol).font(.system(size: 18, weight: .medium)).widgetAccentable()
                Text(route.title).font(.caption2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel("腕聊，\(route.title)")
    }
}

struct WristChatActionsWidget: Widget {
    let kind = "WristChatActions"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WristChatProvider()) { _ in WristChatActionsView() }
            .configurationDisplayName("腕聊快捷操作")
            .description("提问、查看历史或打开设置。")
            .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct WristChatWidgetBundle: WidgetBundle {
    var body: some Widget {
        WristChatAskWidget()
        WristChatActionsWidget()
    }
}
