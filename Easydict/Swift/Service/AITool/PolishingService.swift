//
//  PolishingService.swift
//  Easydict
//
//  Created by Jerry on 2024-07-11.
//  Copyright © 2024 izual. All rights reserved.
//

import Defaults
import Foundation
import SwiftUI

// MARK: - PolishingService

// swiftlint:disable line_length

@objc(EZPolishingService)
class PolishingService: AIToolService {
    // MARK: Public

    public override func name() -> String {
        NSLocalizedString("polishing_service", comment: "")
    }

    public override func serviceType() -> ServiceType {
        .polishing
    }

    /// Polishing runs on DeepSeek, which needs the user's own key.
    ///
    /// The key and endpoint are read from the DeepSeek service's own settings, so
    /// there is one place to configure them: Settings › Services › DeepSeek.
    public override func apiKeyRequirement() -> ServiceAPIKeyRequirement {
        .userProvided
    }

    public override func configurationListItems() -> Any {
        PolishingConfigurationView(service: self)
    }

    // MARK: Internal

    override var apiKey: String {
        deepSeekService.apiKey
    }

    override var endpoint: String {
        deepSeekService.endpoint
    }

    override var defaultModels: [String] {
        [DeepSeekModel.deepseekV4Flash.rawValue]
    }

    override var defaultModel: String {
        DeepSeekModel.deepseekV4Flash.rawValue
    }

    override var observeKeys: [Defaults.Key<String>] {
        [deepSeekService.apiKeyKey, supportedModelsKey]
    }

    var lengthRatioKey: Defaults.Key<PolishingLengthRatio> {
        serviceDefaultsKey(.polishingLengthRatio, defaultValue: .double)
    }

    var lengthRatio: PolishingLengthRatio {
        Defaults[lengthRatioKey]
    }

    /// Streams polished text while enforcing the configured output-length limit.
    override func contentStreamTranslate(
        _ text: String,
        from: Language,
        to: Language
    )
        -> AsyncThrowingStream<String, Error> {
        let ratioPercent = lengthRatio.rawValue
        let contentStream = super.contentStreamTranslate(text, from: from, to: to)

        return AsyncThrowingStream { [weak self] continuation in
            let task = Task {
                do {
                    var limiter = PolishingLengthLimiter(
                        sourceLength: text.count,
                        ratioPercent: ratioPercent
                    )

                    for try await content in contentStream {
                        try Task.checkCancellation()

                        guard !limiter.hasReachedLimit else {
                            self?.cancelStream()
                            continuation.finish()
                            return
                        }

                        let limitedContent = limiter.limit(content)
                        if !limitedContent.isEmpty {
                            continuation.yield(limitedContent)
                        }

                        if limitedContent.count < content.count || limiter.hasReachedLimit {
                            self?.cancelStream()
                            continuation.finish()
                            return
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.cancelStream()
            }
        }
    }

    override func chatMessageDicts(_ chatQuery: ChatQueryParam) -> [ChatMessage] {
        let (text, sourceLanguage, _, _, _) = chatQuery.unpack()
        let prompt = polishingPrompt(text: text, in: sourceLanguage)

        let englishFewShot = [
            chatMessagePair(
                userContent:
                "Polish the following English text to improve its clarity and coherence: \"\"\"The book was wrote by an unknown author but it was very popular among readers.\"\"\"",

                assistantContent:
                "The book was written by an unknown author, but it was very popular among readers."
            ),
            chatMessagePair(
                userContent:
                "Polish the following English text to improve its grammar and readability: \"\"\"She don’t like the weather today, it makes her feel bad.\"\"\"",
                assistantContent: "She doesn't like the weather today; it makes her feel bad."
            ),
            chatMessagePair(
                userContent:
                "Polish the following English text to enhance its overall quality: \"\"\"The project was successful although we faced many problems in the beginning.\"\"\"",
                assistantContent:
                "The project was successful despite facing many problems in the beginning."
            ),
        ].flatMap { $0 }

        var messages: [ChatMessage] = [
            .init(role: .system, content: polishingSystemPrompt),
        ]
        messages.append(contentsOf: englishFewShot)
        messages.append(.init(role: .user, content: prompt))

        return messages
    }

    // MARK: Private

    /// Source of the DeepSeek credentials; holds no polishing state of its own.
    private lazy var deepSeekService = DeepSeekService()

    private let polishingSystemPrompt = """
    You are a text polishing expert skilled in refining and enhancing written content. Your task is to improve the clarity, coherence, grammar, and overall quality of the text while maintaining the original meaning and intent. Focus on correcting grammatical errors, improving sentence structure, and enhancing readability. Ensure the polished text is natural and fluent. Respect the maximum character count stated in the user request. Only return the polished text, without including redundant quotes or additional notes.
    """

    private func polishingPrompt(text: String, in sourceLanguage: Language) -> String {
        let maxLength = PolishingLengthLimiter(
            sourceLength: text.count,
            ratioPercent: lengthRatio.rawValue
        ).maxLength
        return "Polish the following \(sourceLanguage.queryLanguageName) text to improve its clarity, coherence, grammar, and overall quality while maintaining the original meaning and intent. The polished text must contain no more than \(maxLength) characters: \"\"\"\(text)\"\"\""
    }
}

// MARK: - PolishingLengthLimiter

/// Tracks the character budget for one polishing response and truncates each
/// streamed chunk without splitting Swift extended grapheme clusters.
struct PolishingLengthLimiter {
    // MARK: Lifecycle

    init(sourceLength: Int, ratioPercent: Int) {
        self.maxLength = sourceLength * ratioPercent / 100
    }

    // MARK: Internal

    let maxLength: Int
    private(set) var emittedLength = 0

    var hasReachedLimit: Bool {
        emittedLength >= maxLength
    }

    mutating func limit(_ content: String) -> String {
        guard !hasReachedLimit else { return "" }

        let limitedContent = String(content.prefix(maxLength - emittedLength))
        emittedLength += limitedContent.count
        return limitedContent
    }
}

// MARK: - PolishingLengthRatio

/// User-selectable maximum length of polished text relative to its source.
enum PolishingLengthRatio: Int, CaseIterable, Defaults.Serializable {
    case same = 100
    case oneAndHalf = 150
    case double = 200
    case twoAndHalf = 250
    case triple = 300
}

// MARK: EnumLocalizedStringConvertible

extension PolishingLengthRatio: EnumLocalizedStringConvertible {
    var title: LocalizedStringKey {
        LocalizedStringKey("\(rawValue)%")
    }
}

// MARK: - PolishingConfigurationView

/// Service settings for the polishing model and its output-length limit.
private struct PolishingConfigurationView: View {
    let service: PolishingService

    var body: some View {
        ServiceConfigurationSecretSectionView(
            service: service,
            observeKeys: service.observeKeys
        ) {
            PickerCell(
                titleKey: "service.configuration.openai.model.title",
                selectionKey: service.modelKey,
                valuesKey: service.validModelsKey
            )

            StaticPickerCell(
                titleKey: "service.configuration.polishing.max_length_ratio.title",
                key: service.lengthRatioKey,
                values: PolishingLengthRatio.allCases
            )

            StaticPickerCell(
                titleKey: "service.configuration.openai.usage_status.title",
                key: service.serviceUsageStatusKey,
                values: ServiceUsageStatus.allCases
            )

            ToggleCell(
                titleKey: "service.configuration.openai.hide_think_tag_content.title",
                key: service.thinkTagKey
            )

            SliderCell(
                titleKey: "service.configuration.openai.temperature.title",
                storedValueKey: service.temperatureKey
            )
        }
    }
}

// swiftlint:enable line_length
