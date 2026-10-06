// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Text("腕聊")
                        .font(.title2.weight(.semibold))
                    Text("手腕上的 AI 对话与写作。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("个人版 · Apple Watch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink {
                    CopyrightView()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("版权与制作")
                        Text("canonliuliang")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                NavigationLink("数据与 AI 服务") { AboutServicesView() }
            } footer: {
                Text("© 2026 canonliuliang\nGPL-3.0-or-later")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                NavigationLink { InstallationInfoView() } label: {
                    Text("版本与安装")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("关于腕聊")
        .tint(.mint)
        #if DEBUG
        .modifier(AcceptanceTextSize())
        #endif
    }
}

private struct CopyrightView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text("canonliuliang").font(.headline)
                    Text("设计 · 开发 · 制作")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("应用版权") {
                paragraph("© 2026 canonliuliang\nGNU GPL 第3版或更新版本。")
                paragraph("腕聊的程序代码、界面与交互设计、应用图标及原创说明文字，版权归 canonliuliang 所有。")
                paragraph("腕聊是自由软件，可以按 GNU GPL 第3版或更新版本使用、修改和分发，包括商业使用。分发时请保留版权与许可说明，并遵守 GPL 对相同许可和对应源代码的要求。")
                paragraph("本软件不提供任何担保。完整许可随软件附带，也可在 GitHub 的 WristChat 仓库查看。")
                NavigationLink("GPL 许可证全文") { LicenseTextView() }
            }
            Section("第三方权利与致谢") {
                paragraph("Apple、Apple Watch 与 Siri 等名称及标识的相关权利归 Apple Inc. 所有。")
                paragraph("小米 MiMo、DeepSeek 与其他 AI 提供商的名称、模型及服务，相关权利归各自权利人所有。")
                paragraph("腕聊通过各提供商的 API 提供服务，是独立制作的个人应用。使用 SwiftUI、App Intents、WidgetKit 与系统语音能力。")
                paragraph("本页应用版权声明的范围为腕聊自身的原创内容；第三方模型、服务与生成内容的权利，遵循各自适用条款。")
            }
        }
        .navigationTitle("版权与制作")
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 3)
    }
}

private struct AboutServicesView: View {
    var body: some View {
        List {
            Section("对话与密钥") {
                Text("聊天记录与未发送草稿保存在这只手表。配置后的 API 密钥保存在系统钥匙串。")
                Text("生成回答时，问题与选定的上下文会发送至当前 AI 提供商。")
            }
            Section("联网搜索") {
                Text("MiMo 使用其联网搜索服务。DeepSeek 联网时，问题先交由 MiMo 检索，检索资料与来源再交给 DeepSeek 回答。")
                Text("关闭联网搜索后，连接 AI 模型仍需要网络。")
            }
            Section("Siri 与朗读") {
                Text("Siri 提问、追问和作文在后台完成，回答直接交给 Siri。App 内朗读使用系统语音，静音时隐藏朗读入口。")
            }
        }
        .font(.footnote)
        .navigationTitle("数据与 AI 服务")
    }
}

private struct InstallationInfoView: View {
    private let signingExpiration = SigningValidity.expiration(in: .main)
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.7.1"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "11"
    }
    var body: some View {
        List {
            Section("版本") {
                LabeledContent("腕聊", value: version)
                LabeledContent("构建", value: build)
                Text("个人版 · Apple Watch")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("安装信息") {
                Text(SigningValidity.label(for: signingExpiration))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("版本与安装")
    }
}

private struct LicenseTextView: View {
    private let paragraphs: [String] = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ["完整许可证见 GitHub：canonliuliang/WristChat。"] }
        return text.components(separatedBy: "\n\n")
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(paragraphs.indices, id: \.self) { index in
                    Text(paragraphs[index]).font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal)
        }.navigationTitle("GPL v3")
    }
}
