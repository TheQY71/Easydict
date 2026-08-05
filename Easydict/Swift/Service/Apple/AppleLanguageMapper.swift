//
//  AppleLanguageMapper.swift
//  Easydict
//
//  Created by tisfeng on 2025/6/23.
//  Copyright © 2025 izual. All rights reserved.
//

import Foundation
import NaturalLanguage

// MARK: - AppleLanguageMapper

public class AppleLanguageMapper: NSObject {
    // MARK: Public

    /// Returns a dictionary mapping `Language` to `String` for Apple Translation Shortcut.
    public var supportedLanguages: [Language: String] {
        languageMap
    }

    public func language(for appleLanguageCode: String) -> Language? {
        for (key, value) in languageMap where value == appleLanguageCode {
            return key
        }
        return nil
    }

    /// Convert Language to BCP-47 language code for Apple Translation API, supported macOS 15+.
    public func languageCode(for language: Language) -> String {
        switch language {
        case .auto: return "und"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .spanish: return "es"
        case .catalan: return "ca"
        case .portuguese: return "pt"
        case .italian: return "it"
        case .german: return "de"
        case .russian: return "ru"
        case .arabic: return "ar"
        case .thai: return "th"
        case .polish: return "pl"
        case .turkish: return "tr"
        case .indonesian: return "id"
        case .vietnamese: return "vi"
        case .dutch: return "nl"
        case .ukrainian: return "uk"
        case .hindi: return "hi"
        default: return "en"
        }
    }

    /// Convert NLLanguage to Language enum
    public func languageEnum(from appleLanguage: NLLanguage) -> Language {
        for (language, nlLanguage) in appleLanguagesDictionary where nlLanguage == appleLanguage {
            return language
        }
        return .auto
    }

    // MARK: Internal

    static let shared = AppleLanguageMapper()

    /// Returns a dictionary mapping `Language` to `NLLanguage` for Natural Language processing
    ///
    /// This comprehensive mapping provides conversion between Easydict's internal language
    /// enumeration and Apple's Natural Language framework language identifiers. The mapping
    /// follows BCP-47 language tag standards and supports language detection, text processing,
    /// and linguistic analysis throughout the application.
    ///
    /// **Language Tag Format:**
    /// - Uses standard BCP-47 language tags (e.g., "en" for English, "zh-Hans" for Simplified Chinese)
    /// - Includes script subtags where necessary (Hans/Hant for Chinese variants)
    /// - Covers major world languages supported by Apple's Natural Language framework
    ///
    /// **Primary Use Cases:**
    /// - Language detection and identification
    /// - Text processing and linguistic analysis
    /// - Natural language understanding features
    /// - Integration with Apple's ML and NLP frameworks
    ///
    /// - Note: Based on the comprehensive language mapping from the original Objective-C implementation
    var appleLanguagesDictionary: [Language: NLLanguage] {
        [
            .auto: .undetermined, // und
            .simplifiedChinese: .simplifiedChinese, // zh-Hans
            .traditionalChinese: .traditionalChinese, // zh-Hant
            .english: .english, // en
            .japanese: .japanese, // ja
            .korean: .korean, // ko
            .french: .french, // fr
            .spanish: .spanish, // es
            .catalan: .catalan, // ca
            .portuguese: .portuguese, // pt
            .italian: .italian, // it
            .german: .german, // de
            .russian: .russian, // ru
            .arabic: .arabic, // ar
            .swedish: .swedish, // sv
            .romanian: .romanian, // ro
            .thai: .thai, // th
            .slovak: .slovak, // sk
            .dutch: .dutch, // nl
            .hungarian: .hungarian, // hu
            .greek: .greek, // el
            .danish: .danish, // da
            .finnish: .finnish, // fi
            .polish: .polish, // pl
            .czech: .czech, // cs
            .turkish: .turkish, // tr
            .ukrainian: .ukrainian, // uk
            .bulgarian: .bulgarian, // bg
            .indonesian: .indonesian, // id
            .malay: .malay, // ms
            .vietnamese: .vietnamese, // vi
            .persian: .persian, // fa
            .hindi: .hindi, // hi
            .telugu: .telugu, // te
            .tamil: .tamil, // ta
            .urdu: .urdu, // ur
            .khmer: .khmer, // km
            .lao: .lao, // lo
            .bengali: .bengali, // bn
            .burmese: .burmese, // my
            .norwegian: .norwegian, // nb
            .croatian: .croatian, // hr
            .mongolian: .mongolian, // mn
            .hebrew: .hebrew, // he
            .georgian: .georgian, // ka
        ]
    }

    /// Recognized languages for NLLanguageRecognizer and other NLP tasks.
    var recognizedLanguages: [NLLanguage] {
        Array(appleLanguagesDictionary.values)
    }

    /// Custom language hints for improving detection accuracy
    ///
    /// Combines base probability weights with user preference boost.
    /// High weights for common/misdetected languages, lower for distinct patterns.
    /// User preferred languages get +1.0 boost for better UX.
    /// - Helps with "apple" → "en" instead of "tr" problem
    var customLanguageHints: [NLLanguage: Double] {
        // Base language weights optimized for balanced accuracy
        var customHints: [NLLanguage: Double] = [
            // High priority languages (commonly misdetected or very frequent)
            .english: 2.0, // Reduced from 3.0: Still boosted but not overwhelming
            .simplifiedChinese: 1.5, // Reduced from 2.5: Still prioritized
            .traditionalChinese: 1.0, // Keep as reference point

            // Major Asian languages
            .japanese: 0.8, // 門 Reduced from 1.2: Should detect `Traditional Chinese` properly
            .korean: 0.7, // Increased from 0.6: Should detect Korean properly

            // Major European languages (often confused with each other)
            .french: 0.8, // Increased from 0.5: Better French detection
            .spanish: 0.8, // Increased from 0.5: Better Spanish detection
            .italian: 0.6, // Reduced from 0.7 (come)
            .portuguese: 0.7, // Increased from 0.4: Better Portuguese detection
            .german: 0.6, // Increased from 0.3: Better German detection
            .dutch: 0.4, // Increased from 0.25: Better Dutch detection

            // Other European languages
            .russian: 0.8, // Increased from 0.4: Cyrillic script
            .polish: 0.4, // Increased from 0.2: Latin script but distinct
            .czech: 0.3, // Increased from 0.15: Latin script but distinct
            .turkish: 0.08, // Further reduced from 0.2: Often causes false positives
            .catalan: 0.1, // Reduced from 0.15: Often confused with Spanish/French

            // Middle Eastern and others
            .arabic: 0.3, // Distinct script
            .persian: 0.2, // Similar to Arabic but less common
            .thai: 0.3, // Distinct script
            .vietnamese: 0.25, // Latin script with diacritics
            .hindi: 0.2, // Devanagari script

            // Nordic languages
            .swedish: 0.15,
            .danish: 0.15,
            .norwegian: 0.15,
            .finnish: 0.1, // Different language family

            // Less common but supported
            .ukrainian: 0.3, // Cyrillic, similar to Russian
            .bulgarian: 0.15, // Cyrillic
            .romanian: 0.2, // Romance language
            .hungarian: 0.05, // Reduced: Unique language family but often causes false positives
            .greek: 0.2, // Distinct script
            .slovak: 0.05, // Reduced: Similar to Czech, often causes false positives
            .croatian: 0.1, // Reduced: Latin script, can cause confusion
            .indonesian: 0.1, // Reduced: Latin script, can be confused with English
            .malay: 0.08, // Reduced: Similar to Indonesian
        ]

        // Get user preferred languages and boost their weights
        let preferredLanguages = EZLanguageManager.shared().preferredLanguages
        let preferredNLLanguages = preferredLanguages.compactMap { language in
            appleLanguagesDictionary[language]
        }

        // Boost preferred languages
        for preferredLanguage in preferredNLLanguages {
            if let currentWeight = customHints[preferredLanguage] {
                // Add boost based on current weight tier
                let boost = currentWeight >= 2.0 ? 1.5 : 1.0
                customHints[preferredLanguage] = currentWeight + boost
            } else {
                // New preferred language not in base hints
                customHints[preferredLanguage] = 1.0
            }
        }

        // Set default weight for any remaining supported languages
        let supportedLanguages = recognizedLanguages
        for language in supportedLanguages where !customHints.keys.contains(language) {
            customHints[language] = 0.05 // Lower default to avoid false positives
        }

        return customHints
    }

    // MARK: Private

    /// Apple Translation Shortcut supported languages map.
    private let languageMap: [Language: String] = [
        .auto: "auto",
        .simplifiedChinese: "zh_CN",
        .traditionalChinese: "zh_TW",
        .english: "en_US",
        .japanese: "ja_JP",
        .korean: "ko_KR",
        .french: "fr_FR",
        .spanish: "es_ES",
        .portuguese: "pt_BR",
        .italian: "it_IT",
        .german: "de_DE",
        .russian: "ru_RU",
        .arabic: "ar_AE",
        .thai: "th_TH",
        .polish: "pl_PL",
        .turkish: "tr_TR",
        .indonesian: "id_ID",
        .vietnamese: "vi_VN",
        // macOS 14+
        .dutch: "nl_NL",
        .ukrainian: "uk_UA",
        // macOS 15+
        .hindi: "hi_IN",
    ]
}
