//
//  SettingView.swift
//  Easydict
//
//  Created by Kyle on 2023/12/29.
//  Copyright © 2023 izual. All rights reserved.
//

import SFSafeSymbols
import SwiftUI

// MARK: - SettingTab

enum SettingTab: Int {
    case general
    case service
    case disabled
    case advanced
    case shortcut
    case privacy
    case favorites
    case about
}

// MARK: - SettingView

struct SettingView: View {
    // MARK: Internal

    var body: some View {
        TabView(selection: $selection) {
            GeneralTab()
                .tabItem { Label("setting_general", systemSymbol: .gear) }
                .tag(SettingTab.general)

            ServiceTab()
                .tabItem { Label("service", systemSymbol: .briefcase) }
                .tag(SettingTab.service)

            FavoritesTab()
                .tabItem { Label("favorites.tab", systemSymbol: .star) }
                .tag(SettingTab.favorites)

            DisabledAppTab()
                .tabItem { Label("disabled_app_list", systemSymbol: .nosign) }
                .tag(SettingTab.disabled)

            ShortcutTab()
                .tabItem { Label("shortcut", systemSymbol: .commandSquare) }
                .tag(SettingTab.shortcut)

            AdvancedTab()
                .tabItem { Label("advanced", systemSymbol: .gearshape2) }
                .tag(SettingTab.advanced)

            PrivacyTab()
                .tabItem { Label("privacy", systemSymbol: .handRaisedSquare) }
                .tag(SettingTab.privacy)

            AboutTab()
                .tabItem { Label("setting.about", systemSymbol: .infoBubble) }
                .tag(SettingTab.about)
        }
        .background(
            WindowAccessor(window: $window.didSet(execute: { _ in
                // reset frame when first launch
                resizeWindowFrame()
            }))
        )
        .onChange(of: selection) { _ in
            resizeWindowFrame()
        }
    }

    func resizeWindowFrame() {
        guard let window else { return }

        // Disable zoom button, refer: https://stackoverflow.com/a/66039864/8378840
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        // Keep the settings page Windows all the same width to avoid strange animations.
        let maxWidth: Double = 900
        let height: Double = switch selection {
        case .disabled:
            500
        case .privacy:
            340
        case .about:
            300
        case .favorites:
            640
        default:
            maxWidth * 0.8
        }

        let newSize = CGSize(width: maxWidth, height: height)

        let originalFrame = window.frame
        let newY = originalFrame.origin.y + originalFrame.size.height - newSize.height
        let newRect = NSRect(origin: CGPoint(x: originalFrame.origin.x, y: newY), size: newSize)

        window.setFrame(newRect, display: true, animate: false)
        window.styleMask.remove(.resizable)
    }

    // MARK: Private

    @State private var selection = SettingTab.general
    @State private var window: NSWindow?
}

#Preview {
    SettingView()
}
