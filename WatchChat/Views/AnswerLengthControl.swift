// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import SwiftUI

/// Three discrete options use the system's full-screen watch picker.
struct AnswerLengthControl: View {
    @Binding var selection: AnswerLength

    var body: some View {
        Picker("回答长度", selection: $selection) {
            ForEach(AnswerLength.allCases, id: \.self) { length in
                Text(length.title).tag(length)
            }
        }
        .pickerStyle(.navigationLink)
    }
}
