// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

struct WritingTargetControl: View {
    @Binding var target: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("目标字数").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { adjust(-100) } label: {
                    Image(systemName: "minus").frame(width: 36, height: 40)
                }.disabled(target <= 100).accessibilityLabel("减少100字")
                Spacer(minLength: 0)
                Text("\(target)字").font(.title3).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button { adjust(100) } label: {
                    Image(systemName: "plus").frame(width: 36, height: 40)
                }.disabled(target >= 2400).accessibilityLabel("增加100字")
            }.buttonStyle(.plain).foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("目标字数")
        .accessibilityValue("\(target)字")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(100)
            case .decrement: adjust(-100)
            @unknown default: break
            }
        }
    }
    private func adjust(_ amount: Int) { target = min(2400, max(100, target + amount)) }
}
