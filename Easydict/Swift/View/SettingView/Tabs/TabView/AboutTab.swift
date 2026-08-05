//
//  AboutTab.swift
//  Easydict
//
//  Created by Kyle on 2023/10/29.
//  Copyright © 2023 izual. All rights reserved.
//

import SFSafeSymbols
import SwiftUI

// MARK: - AboutTab

/// The About pane of the settings window.
///
/// Presents the app icon, name, version, and copyright in a centered
/// column, followed by a row of links to the repository, the contributor
/// list, and the acknowledgements window.
struct AboutTab: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 16) {
            Image(.logo)
                .resizable()
                .renderingMode(.original)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    Text(appName)
                        .font(.title2.weight(.semibold))

                    Text("current_version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(copyrightInfo)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(
                        URL(string: "https://github.com/tisfeng/Easydict")!
                    )
                } label: {
                    Label("setting.about.github_link", systemSymbol: .starFill)
                }

                Button {
                    NSWorkspace.shared.open(
                        URL(
                            string: "https://github.com/tisfeng/Easydict/graphs/contributors"
                        )!
                    )
                } label: {
                    Label("setting.about.contributor_link", systemSymbol: .person3Fill)
                }

                Button {
                    HostWindowManager.shared.showAcknowWindow()
                } label: {
                    Label("setting.about.acknowledgements", systemSymbol: .checkmarkSealFill)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? ""
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var copyrightInfo: String {
        Bundle.main.localizedString(
            forKey: "NSHumanReadableCopyright",
            value: "Copyright © 2023-2025 tisfeng. All rights reserved.",
            table: "InfoPlist"
        )
    }
}

#Preview {
    AboutTab()
}
