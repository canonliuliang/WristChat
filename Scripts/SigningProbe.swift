// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

@main
struct SigningProbe {
    static func main() throws {
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let bundle = Bundle(url: appURL), let actual = SigningValidity.expiration(in: bundle) else {
            fatalError("Unable to read installed signing metadata")
        }
        let extensions = try FileManager.default.contentsOfDirectory(
            at: appURL.appendingPathComponent("PlugIns"), includingPropertiesForKeys: nil)
        let profiles = ([appURL] + extensions.filter { $0.pathExtension == "appex" })
            .map { $0.appendingPathComponent("embedded.mobileprovision") }
        let dates = try profiles.map { profile -> Date in
            let decoder = Process()
            decoder.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            decoder.arguments = ["cms", "-D", "-i", profile.path]
            let output = Pipe()
            decoder.standardOutput = output
            decoder.standardError = Pipe()
            try decoder.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            decoder.waitUntilExit()
            guard decoder.terminationStatus == 0,
                  let fields = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let expected = fields["ExpirationDate"] as? Date else {
                fatalError("System profile decoder failed")
            }
            return expected
        }
        precondition(actual == dates.min(), "App expiry must match the earliest signed profile")
        let result: [String: Any] = ["profileCount": dates.count,
            "expirationUTC": ISO8601DateFormatter().string(from: actual),
            "displayLabel": SigningValidity.label(for: actual), "matchesSystemDecoder": true]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
