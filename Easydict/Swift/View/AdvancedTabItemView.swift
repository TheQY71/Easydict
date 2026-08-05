//
//  AdvancedTabItemView.swift
//  Easydict
//
//  Created by Jerry on 2024-05-06.
//  Copyright © 2024 izual. All rights reserved.
//

import SFSafeSymbols
import SwiftUI

/// Row label for the Advanced settings tab: a monochrome symbol chip, a
/// title, and an optional subtitle. The chip is deliberately colorless so a
/// long list of rows reads as one calm column instead of a rainbow.
struct AdvancedTabItemView: View {
    let icon: SFSymbol
    let labelText: LocalizedStringKey
    var subtitleText: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemSymbol: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(labelText)
                if let subtitleText {
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // FIXME: It seems that Toggle does not align with the AdvancedTabItemView. We need to fix this.
        .alignmentGuide(.firstTextBaseline) { context in
            if subtitleText != nil {
                context[VerticalAlignment.center]
            } else {
                context[.firstTextBaseline]
            }
        }
    }
}
