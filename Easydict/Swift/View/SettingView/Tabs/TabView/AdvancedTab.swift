//
//  AdvancedTab.swift
//  Easydict
//
//  Created by tisfeng on 2024/1/23.
//  Copyright © 2024 izual. All rights reserved.
//

import Defaults
import SFSafeSymbols
import SwiftUI

struct AdvancedTab: View {
    // MARK: Internal

    // Query text processing
    @Default(.replaceNewlineWithSpace) var replaceNewlineWithSpace: Bool
    @Default(.automaticallyRemoveCodeCommentSymbols) var automaticallyRemoveCodeCommentSymbols: Bool
    @Default(.automaticWordSegmentation) var automaticWordSegmentation: Bool

    var body: some View {
        Form {
            // Quick chat backend, first because it is this fork's core feature.
            Section {
                Picker(
                    selection: $quickChatServiceType,
                    label: AdvancedTabItemView(
                        icon: .bubbleLeftAndBubbleRight,
                        labelText: "setting.advance.quick_chat_service",
                        subtitleText: "setting.advance.quick_chat_service_desc"
                    )
                ) {
                    ForEach(quickChatServiceOptions, id: \.typeID) { option in
                        Text(option.title)
                            .tag(option.typeID)
                    }
                }
                .onChange(of: quickChatServiceType) { _ in
                    quickChatModel = currentQuickChatModel
                }

                if !quickChatModelOptions.isEmpty {
                    Picker(
                        selection: $quickChatModel,
                        label: AdvancedTabItemView(
                            icon: .cpu,
                            labelText: "setting.advance.quick_chat_model"
                        )
                    ) {
                        ForEach(quickChatModelOptions, id: \.self) { model in
                            Text(model)
                                .tag(model)
                        }
                    }
                    .onAppear { quickChatModel = currentQuickChatModel }
                    .onChange(of: quickChatModel) { newModel in
                        applyQuickChatModel(newModel)
                    }
                }
            } header: {
                Text("setting.advance.header.quick_chat")
            }

            // General settings section
            Section {
                Toggle(isOn: $enableBetaFeature) {
                    AdvancedTabItemView(
                        icon: .hammerFill,
                        labelText: "setting.advance.enable_beta_feature"
                    )
                }
                Picker(
                    selection: $defaultTTSServiceType,
                    label: AdvancedTabItemView(
                        icon: .ellipsisBubbleFill,
                        labelText: "setting.advance.default_tts_service"
                    )
                ) {
                    ForEach(TTSServiceType.allCases, id: \.rawValue) { option in
                        Text(option.localizedStringResource)
                            .tag(option)
                    }
                }
                Toggle(isOn: $preferYoudaoTTSForEnglishWord) {
                    AdvancedTabItemView(
                        icon: .waveform,
                        labelText: "setting.advance.prefer_youdao_tts_for_english_word",
                        subtitleText: "setting.advance.prefer_youdao_tts_for_english_word_desc"
                    )
                }
                Toggle(isOn: $disableTipsView) {
                    AdvancedTabItemView(
                        icon: .lightbulbFill,
                        labelText: "setting.advance.disable_tips_view"
                    )
                }

                // Require macOS 15+
                if #available(macOS 15.0, *) {
                    Toggle(isOn: $enableLocalAppleTranslation) {
                        AdvancedTabItemView(
                            icon: .appleLogo,
                            labelText: "setting.advance.apple_offline_translation",
                            subtitleText: "setting.advance.apple_offline_translation_desc"
                        )
                    }
                }

                LabeledContent {
                    TextField(
                        text: $minClassicalChineseTextDetectLength,
                        prompt: Text(verbatim: "\(SharedConstants.minClassicalChineseLength)")
                    ) {
                        EmptyView()
                    }
                    .frame(width: 100)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: minClassicalChineseTextDetectLength) { newValue in
                        minClassicalChineseTextDetectLength = newValue.filter { $0.isNumber }
                        logInfo(
                            "Min classical Chinese text detect length: \(minClassicalChineseTextDetectLength)"
                        )
                    }
                } label: {
                    AdvancedTabItemView(
                        icon: .book,
                        labelText: "setting.advance.min_classical_chinese_text_detect_length"
                    )
                }
            } header: {
                Text("setting.advance.header.general_settings")
            }

            // Mouse query icon
            Section {
                let minLengthBinding = Binding<Double>(
                    get: {
                        Double(min(50, max(0, autoShowQueryIconMinTextLength)))
                    },
                    set: { newValue in
                        autoShowQueryIconMinTextLength = min(50, max(0, Int(newValue)))
                    }
                )

                Toggle(isOn: $autoShowQueryIcon) {
                    AdvancedTabItemView(
                        icon: .cursorarrowRays,
                        labelText: "setting.advance.auto_show_query_icon"
                    )
                }

                Group {
                    LabeledContent {
                        Picker(selection: $autoShowQueryIconExcludedLanguage) {
                            ForEach(Language.allAvailableOptions, id: \.rawValue) { option in
                                Text(verbatim: "\(option.flagEmoji) \(option.localizedName)")
                                    .tag(option)
                            }
                        } label: {
                            EmptyView()
                        }
                        .labelsHidden()
                    } label: {
                        Text("setting.advance.auto_show_query_icon.condition.language")
                    }

                    LabeledContent {
                        HStack(spacing: 8) {
                            Slider(value: minLengthBinding, in: 0 ... 50, step: 10)
                            Text("\(autoShowQueryIconMinTextLength)")
                                .frame(width: 32, alignment: .trailing)
                                .monospacedDigit()
                        }
                    } label: {
                        Text("setting.advance.auto_show_query_icon.condition.min_length")
                    }

                    Text("setting.advance.auto_show_query_icon.condition.desc")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 28)
                .disabled(!autoShowQueryIcon)
                .opacity(autoShowQueryIcon ? 1 : 0.6)

                Toggle(isOn: $clickQuery) {
                    AdvancedTabItemView(
                        icon: .cursorarrowClick,
                        labelText: "setting.advance.click_icon_query_info"
                    )
                }
            } header: {
                Text("setting.advance.mouse_select_query.header")
            }

            // Force get selected text and replace text
            Section {
                Toggle(isOn: $enableForceGetSelectedText) {
                    AdvancedTabItemView(
                        icon: .characterCursorIbeam,
                        labelText: "setting.advance.enable_force_get_selected_text",
                        subtitleText: "setting.advance.enable_force_get_selected_text_desc"
                    )
                }

                Picker(
                    selection: $forceGetSelectedTextType,
                    label: AdvancedTabItemView(
                        icon: .highlighter,
                        labelText: "setting.advance.force_get_selected_text_type"
                    )
                ) {
                    ForEach(ForceGetSelectedTextType.allCases, id: \.rawValue) { option in
                        Text(option.localizedStringResource)
                            .tag(option)
                    }
                }

                Toggle(isOn: $preferAppleScriptAPI) {
                    AdvancedTabItemView(
                        icon: .applescript,
                        labelText: "setting.advance.prefer_applescript_api",
                        subtitleText: "setting.advance.prefer_applescript_api_desc"
                    )
                }
                Toggle(isOn: $enableCompatibilityReplace) {
                    AdvancedTabItemView(
                        icon: .arrowForwardSquare,
                        labelText: "setting.advance.enable_compatibility_replace",
                        subtitleText: "setting.advance.enable_compatibility_replace_desc"
                    )
                }
                Toggle(isOn: $autoSelectAllTextFieldText) {
                    AdvancedTabItemView(
                        icon: .checkmarkSquare,
                        labelText: "setting.advance.auto_select_all_text_field_text",
                        subtitleText: "setting.advance.auto_select_all_text_field_text_desc"
                    )
                }
                Toggle(isOn: $enableRemoveBooksExcerptInfo) {
                    AdvancedTabItemView(
                        icon: .book,
                        labelText: "setting.advance.enable_remove_books_excerpt_info"
                    )
                }
            } header: {
                Text("setting.advance.header.text_selection_and_replacement")
            }

            // Query text processing
            Section {
                Toggle(isOn: $replaceNewlineWithSpace) {
                    AdvancedTabItemView(
                        icon: .arrowForwardSquare,
                        labelText: "setting.advance.automatically_replace_newline_with_space"
                    )
                }
                Toggle(isOn: $automaticallyRemoveCodeCommentSymbols) {
                    AdvancedTabItemView(
                        icon: .chevronLeftForwardslashChevronRight,
                        labelText: "setting.advance.automatically_remove_code_comment_symbols"
                    )
                }
                Toggle(isOn: $automaticWordSegmentation) {
                    AdvancedTabItemView(
                        icon: .textWordSpacing,
                        labelText: "setting.advance.automatically_split_words"
                    )
                }
            } header: {
                Text("setting.advance.header.query_text_processing")
            } footer: {
                Text("setting.advance.footer.query_text_processing_desc")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Windows management
            Section {
                Picker(
                    selection: $mouseSelectTranslateWindowType,
                    label: AdvancedTabItemView(
                        icon: .cursorarrowRays,
                        labelText: "setting.advance.window.mouse_select_translate_window_type"
                    )
                ) {
                    ForEach(EZWindowType.availableOptions, id: \.rawValue) { option in
                        Text(option.localizedStringResource)
                            .tag(option)
                    }
                }

                Picker(
                    selection: $shortcutSelectTranslateWindowType,
                    label: AdvancedTabItemView(
                        icon: .keyboardFill,
                        labelText: "setting.advance.window.shortcut_select_translate_window_type"
                    )
                ) {
                    ForEach(EZWindowType.availableOptions, id: \.rawValue) { option in
                        Text(option.localizedStringResource)
                            .tag(option)
                    }
                }

                Picker(
                    selection: $fixedWindowPosition,
                    label: AdvancedTabItemView(
                        icon: .textAndCommandMacwindow,
                        labelText: "setting.advance.window.fixed_window_position"
                    )
                ) {
                    ForEach(EZShowWindowPosition.allCases, id: \.rawValue) { option in
                        Text(option.localizedStringResource)
                            .tag(option)
                    }
                }

                Picker(
                    selection: $miniWindowPosition,
                    label: AdvancedTabItemView(
                        icon: .macwindow,
                        labelText: "setting.advance.window.mini_window_position"
                    )
                ) {
                    ForEach(EZShowWindowPosition.allCases, id: \.rawValue) { option in
                        Text(option.localizedStringResource)
                            .tag(option)
                    }
                }

                Toggle(isOn: $pinWindowWhenDisplayed) {
                    AdvancedTabItemView(
                        icon: .pinFill,
                        labelText: "setting.advance.pin_window_when_showing"
                    )
                }

                Toggle(isOn: $hideMainWindow) {
                    AdvancedTabItemView(
                        icon: .eyeSlashFill,
                        labelText: "setting.advance.hide_main_window"
                    )
                }

                Picker(
                    selection: $maxWindowHeightPercentageValue,
                    label: AdvancedTabItemView(
                        icon: .arrowUpAndDown,
                        labelText: "setting.advance.window.max_height_percentage"
                    )
                ) {
                    ForEach(MaxWindowHeightPercentageOption.allCases) { option in
                        Text(option.title)
                            .tag(option)
                    }
                    .onChange(of: maxWindowHeightPercentageValue) { _ in
                        // Post notification when max window height percentage changes
                        NotificationCenter.default.post(
                            name: .maxWindowHeightSettingsChanged, object: nil
                        )
                    }
                }

            } header: {
                Text("setting.advance.window_management.header")
            }

            // HTTP server
            Section {
                Toggle(isOn: $enableHTTPServer) {
                    AdvancedTabItemView(
                        icon: .network,
                        labelText: "setting.advance.enable_http_server"
                    )
                }

                LabeledContent {
                    TextField(text: $httpPort, prompt: Text(verbatim: "8080")) {
                        EmptyView()
                    }
                    .frame(width: 100)
                    .fixedSize(horizontal: true, vertical: false)
                    // Add onChange modifier to filter input
                    .onChange(of: httpPort) { newValue in
                        httpPort = newValue.filter { $0.isNumber }
                    }
                } label: {
                    AdvancedTabItemView(
                        icon: .externaldriveConnectedToLineBelow,
                        labelText: "setting.advance.http_port",
                        subtitleText: "setting.advance.http_port_desc"
                    )
                }
            } header: {
                Text("setting.advance.header.http_server")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    @State private var quickChatModel = ""

    @Default(.enableBetaFeature) private var enableBetaFeature

    @Default(.defaultTTSServiceType) private var defaultTTSServiceType
    @Default(.quickChatServiceType) private var quickChatServiceType

    @Default(.preferYoudaoTTSForEnglishWord) private var preferYoudaoTTSForEnglishWord
    @Default(.disableTipsView) private var disableTipsView
    @Default(.enableCompatibilityReplace) private var enableCompatibilityReplace
    @Default(.enableAppleOfflineTranslation) private var enableLocalAppleTranslation
    @Default(.minClassicalChineseTextDetectLength) private var minClassicalChineseTextDetectLength
    @Default(.autoSelectAllTextFieldText) private var autoSelectAllTextFieldText
    @Default(.preferAppleScriptAPI) private var preferAppleScriptAPI

    // Force get selected text
    @Default(.enableForceGetSelectedText) private var enableForceGetSelectedText
    @Default(.forceGetSelectedTextType) private var forceGetSelectedTextType

    // mouse select from Books.app
    @Default(.enableRemoveBooksExcerptInfo) private var enableRemoveBooksExcerptInfo

    // Mouse select query
    @Default(.autoShowQueryIcon) private var autoShowQueryIcon
    @Default(.autoShowQueryIconExcludedLanguage) private var autoShowQueryIconExcludedLanguage
    @Default(.autoShowQueryIconMinTextLength) private var autoShowQueryIconMinTextLength
    @Default(.clickQuery) private var clickQuery

    // Windows management
    @Default(.fixedWindowPosition) private var fixedWindowPosition
    @Default(.miniWindowPosition) private var miniWindowPosition
    @Default(.mouseSelectTranslateWindowType) private var mouseSelectTranslateWindowType
    @Default(.shortcutSelectTranslateWindowType) private var shortcutSelectTranslateWindowType
    @Default(.pinWindowWhenDisplayed) private var pinWindowWhenDisplayed
    @Default(.hideMainWindow) private var hideMainWindow

    @Default(.enableHTTPServer) private var enableHTTPServer
    @Default(.httpPort) private var httpPort

    @Default(.maxWindowHeightPercentage) private var maxWindowHeightPercentageValue

    /// Models the quick chat service supports, empty when it has none configured.
    private var quickChatModelOptions: [String] {
        quickChatStreamService?.validModels ?? []
    }

    private var currentQuickChatModel: String {
        quickChatStreamService?.model ?? ""
    }

    /// A throwaway instance of the quick chat service, used to read and write its
    /// `Defaults`-backed model setting.
    private var quickChatStreamService: StreamService? {
        QueryServiceFactory.shared.service(withTypeId: quickChatServiceType) as? StreamService
    }

    /// Stream-capable services offered as the quick chat backend.
    private var quickChatServiceOptions: [(typeID: String, title: String)] {
        let factory = QueryServiceFactory.shared
        return factory.allServiceTypeIDs.compactMap { typeID in
            guard let metadata = factory.metadata(withTypeId: typeID), metadata.isStream else {
                return nil
            }
            return (typeID: typeID, title: metadata.title)
        }
    }

    /// Writes the model back to the service. The setting is the service's own, so
    /// the choice is shared with that service's translation configuration.
    private func applyQuickChatModel(_ model: String) {
        guard !model.isEmpty, let service = quickChatStreamService, service.model != model else {
            return
        }
        service.model = model
    }
}

#Preview {
    AdvancedTab()
}
