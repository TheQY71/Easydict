//
//  WindowConfiguration.swift
//  Easydict
//
//  Created by tisfeng on 2024/10/24.
//  Copyright © 2024 izual. All rights reserved.
//

import Defaults
import SwiftUI

// MARK: - WindowConfigurationView

/// Window appearance toggles shared by every query window. Storage is a
/// single unified copy (see `windowConfigurationKey`); changes broadcast so
/// every open query window refreshes immediately.
struct WindowConfigurationView: View {
    // MARK: Lifecycle

    init() {
        _showInputTextField = .init(
            windowConfigurationKey(
                .inputFieldCellVisible, windowType: .fixed, defaultValue: true
            )
        )

        _showSelectLanguageTextField = .init(
            windowConfigurationKey(
                .selectLanguageCellVisible, windowType: .fixed, defaultValue: true
            )
        )
    }

    // MARK: Internal

    @Default var showInputTextField: Bool
    @Default var showSelectLanguageTextField: Bool

    var body: some View {
        Form {
            Section {
                NotifyingToggle(
                    title: "setting.service.show_input_text_field",
                    isOn: $showInputTextField
                )

                NotifyingToggle(
                    title: "setting.service.show_select_language_bar",
                    isOn: $showSelectLanguageTextField
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - NotifyingToggle

/// Toggle bound to a unified window-configuration flag. The binding writes
/// the single stored value and broadcasts one window-neutral notification.
struct NotifyingToggle: View {
    let title: LocalizedStringKey

    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .onChange(of: isOn) { _ in
                NotificationCenter.default.post(
                    name: .didChangeWindowConfiguration,
                    object: nil
                )
            }
    }
}
