// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

enum SigningValidity {
    static func expiration(in bundle: Bundle) -> Date? {
        var bundles = [bundle.bundleURL]
        let plugins = bundle.bundleURL.appendingPathComponent("PlugIns", isDirectory: true)
        if let extensions = try? FileManager.default.contentsOfDirectory(at: plugins,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            bundles += extensions.filter { $0.pathExtension == "appex" }
        }
        // The app and its extensions must all remain valid.
        let dates = bundles.compactMap {
            expiration(from: $0.appendingPathComponent("embedded.mobileprovision"))
        }
        guard dates.count == bundles.count else { return nil }
        return dates.min()
    }

    static func expiration(from profileURL: URL) -> Date? {
        guard let data = try? Data(contentsOf: profileURL, options: [.mappedIfSafe]),
              data.count <= 2_000_000,
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8),
                  in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], options: [], format: nil),
              let fields = plist as? [String: Any] else { return nil }
        return fields["ExpirationDate"] as? Date
    }

    static func label(for expiration: Date?) -> String {
        #if targetEnvironment(simulator)
        return "模拟器无需签名"
        #else
        guard let expiration else { return "签名日期暂不可读" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return "签名至 \(formatter.string(from: expiration))"
        #endif
    }
}
