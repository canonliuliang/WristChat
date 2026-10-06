// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI
import AuthenticationServices
import Combine

@MainActor
final class SourceBrowser: ObservableObject {
    @Published private(set) var error: String?
    private var session: ASWebAuthenticationSession?
    private var token: UUID?

    func open(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else {
            error = "来源地址无法打开。"; return
        }
        error = nil
        let identifier = UUID(); token = identifier
        session?.cancel()
        // watchOS has no public WKWebView. Its system web session displays the
        // original page on the watch; an ephemeral session doesn't share logins.
        let browser = ASWebAuthenticationSession(url: url, callback: .customScheme("wristchat-web-close")) { [weak self] _, failure in
            let code = (failure as NSError?)?.code
            Task { @MainActor in
                guard let self, self.token == identifier else { return }
                self.session = nil; self.token = nil
                if let code, code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    self.error = "网页暂时无法打开，请稍后重试。"
                }
            }
        }
        browser.prefersEphemeralWebBrowserSession = true
        session = browser
        if !browser.start() { session = nil; token = nil; error = "手表暂时无法打开网页，请稍后重试。" }
    }
}

struct SourcesView: View {
    let sources: [SearchSource]
    @StateObject private var browser = SourceBrowser()
    var body: some View {
        List {
            Section {
                ForEach(sources) { source in
                    Button { browser.open(source.url) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title).font(.body)
                            HStack(spacing: 4) {
                                Text(source.site)
                                Image(systemName: "arrow.up.right")
                            }.font(.caption2).foregroundStyle(.secondary)
                        }
                    }.accessibilityLabel("在手表打开\(source.title)，\(source.site)")
                }
            } footer: { Text("点按在手表查看原网页。网页内容与显示方式由来源网站决定。") }
            if let error = browser.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.navigationTitle("搜索来源")
    }
}
