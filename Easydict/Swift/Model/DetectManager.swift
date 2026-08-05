//
//  DetectManager.swift
//  Easydict
//
//  Created by tisfeng on 2022/11/5.
//  Copyright © 2024 izual. All rights reserved.
//

import Foundation
import SystemConfiguration

// MARK: - DetectManager

/// Manager for query text language detection.
/// Coordinates Apple, Google, and Baidu detection services to resolve the source
/// language of the current query, applying the configured optimization strategy.
@objc(EZDetectManager)
@objcMembers
public final class DetectManager: NSObject {
    // MARK: Lifecycle

    /// Initializes a new detect manager with the specified query model.
    /// - Parameter model: The query model containing the text to detect.
    public init(model: QueryModel) {
        self.queryModel = model
        super.init()
    }

    /// Initializes a new detect manager with an empty query model.
    public override convenience init() {
        self.init(model: QueryModel())
        self.allowsDetachedDetection = true
    }

    // MARK: Public

    /// The query model containing the text to be processed.
    public var queryModel: QueryModel

    // MARK: - Static Factory

    /// Creates a new detect manager with the specified query model.
    /// - Parameter model: The query model containing the text to detect.
    /// - Returns: A new detect manager instance.
    @objc(managerWithModel:)
    public static func manager(with model: QueryModel) -> DetectManager {
        DetectManager(model: model)
    }

    // MARK: - Public Methods

    /// Detects the language of the given text using Apple, Google, and/or Baidu services    /// Detects the language of the given text using Apple, Google, and/or Baidu services
    /// based on the configured language detection optimization setting.
    /// - Parameters:
    ///   - queryText: The text to detect the language of.
    ///   - completion: Callback with the updated query model and optional error.
    public func detectText(_ queryText: String, completion: @escaping (QueryModel, Error?) -> ()) {
        guard !queryText.isEmpty else {
            let errorMessage = "detectText cannot be nil"
            logError(errorMessage)
            completion(queryModel, QueryError.error(type: .parameter, message: errorMessage))
            return
        }

        appleService.detectText(queryText) { [weak self] appleDetectedLanguage, error in
            guard let self else {
                completion(QueryModel(), error)
                return
            }
            guard canApplyDetectedLanguage(for: queryText) else {
                completion(queryModel, staleDetectionError())
                return
            }

            var preferredLanguages = EZLanguageManager.shared().preferredLanguages

            // Add English and Chinese to the preferred language list.
            // System detect for English and Chinese is relatively accurate,
            // so we don't need to use Google or Baidu to detect again.
            preferredLanguages.append(contentsOf: [
                .english,
                .simplifiedChinese,
                .traditionalChinese,
            ])

            let isPreferredLanguage = preferredLanguages.contains(appleDetectedLanguage)

            let languageDetectOptimize = MyConfiguration.shared.languageDetectOptimize

            // If the detected language is preferred or optimization is disabled, use Apple's result.
            if isPreferredLanguage || languageDetectOptimize == .none {
                handleDetectedLanguage(
                    appleDetectedLanguage,
                    queryText: queryText,
                    error: error,
                    completion: completion
                )
                return
            }

            // Otherwise, use configured optimization service (Baidu or Google).
            if languageDetectOptimize == .baidu {
                baiduDetect(
                    queryText: queryText,
                    fallbackLanguage: appleDetectedLanguage,
                    fallbackError: error,
                    completion: completion
                )
                return
            }

            if languageDetectOptimize == .google {
                googleDetect(
                    queryText: queryText,
                    fallbackLanguage: appleDetectedLanguage,
                    fallbackError: error,
                    completion: completion
                )
                return
            }
        }
    }

    /// Checks if a system proxy is configured.    /// Checks if a system proxy is configured.
    /// - Returns: `true` if an HTTP proxy is enabled, `false` otherwise.
    @objc(checkIfHasProxy)
    public func checkIfHasProxy() -> Bool {
        guard let proxies = SCDynamicStoreCopyProxies(nil) as? [String: Any] else {
            return false
        }

        let httpProxy = proxies[kSCPropNetProxiesHTTPEnable as String] as? Bool
        let httpEnable = proxies[kSCPropNetProxiesHTTPEnable as String] as? Int

        return (httpProxy == true) || (httpEnable == 1)
    }

    // MARK: Private

    // MARK: - Private Properties

    private var allowsDetachedDetection = false

    private lazy var appleService: AppleService = .shared

    private lazy var googleService: GoogleService = .init()

    private lazy var baiduService: BaiduService = .init()

    // MARK: - Private Methods

    private func canApplyDetectedLanguage(for queryText: String) -> Bool {
        allowsDetachedDetection || queryModel.queryText == queryText
    }

    private func staleDetectionError() -> QueryError {
        QueryError.error(type: .parameter, message: "Stale language detection result")
    }

    /// Handles the detected language by updating the query model    /// Handles the detected language by updating the query model and calling the completion handler.
    /// - Parameters:
    ///   - language: The detected language.
    ///   - error: Optional error from detection.
    ///   - completion: Callback to invoke with the updated query model and error.
    private func handleDetectedLanguage(
        _ language: Language,
        queryText: String,
        error: Error?,
        completion: @escaping (QueryModel, Error?) -> ()
    ) {
        guard canApplyDetectedLanguage(for: queryText) else {
            completion(queryModel, staleDetectionError())
            return
        }
        queryModel.detectedLanguage = language

        // If detection succeeded, we don't need to detect again temporarily.
        queryModel.needDetectLanguage = (error != nil)

        completion(queryModel, error)
    }

    /// Detects language using Baidu's service as a fallback.    /// Detects language using Baidu's service as a fallback.
    /// - Parameters:
    ///   - queryText: The text to detect.
    ///   - fallbackLanguage: The language to use if Baidu detection fails.
    ///   - fallbackError: The error from the previous detection attempt.
    ///   - completion: Callback to invoke with the updated query model and error.
    private func baiduDetect(
        queryText: String,
        fallbackLanguage: Language,
        fallbackError: Error?,
        completion: @escaping (QueryModel, Error?) -> ()
    ) {
        baiduService.detectText(queryText) { [weak self] language, error in
            guard let self else {
                completion(QueryModel(), error)
                return
            }

            let detectedLanguage = error == nil ? language : fallbackLanguage

            if error == nil {
                logInfo("Baidu detected: \(language)")
            } else {
                logError("Baidu detect error: \(error?.localizedDescription ?? "unknown")")
            }

            handleDetectedLanguage(
                detectedLanguage,
                queryText: queryText,
                error: error ?? fallbackError,
                completion: completion
            )
        }
    }

    /// Detects language using Google's service as a primary fallback,
    /// then Baidu's service if Google fails.
    /// - Parameters:
    ///   - queryText: The text to detect.
    ///   - fallbackLanguage: The language to use if all detection attempts fail.
    ///   - fallbackError: The error from the previous detection attempt.
    ///   - completion: Callback to invoke with the updated query model and error.
    private func googleDetect(
        queryText: String,
        fallbackLanguage: Language,
        fallbackError: Error?,
        completion: @escaping (QueryModel, Error?) -> ()
    ) {
        googleService.detectText(queryText) { [weak self] language, error in
            guard let self else {
                completion(QueryModel(), error)
                return
            }

            if error == nil {
                logInfo("Google detected: \(language)")
                handleDetectedLanguage(
                    language,
                    queryText: queryText,
                    error: nil,
                    completion: completion
                )
                return
            }

            logError("Google detect error: \(error?.localizedDescription ?? "unknown")")

            // If Google detection failed, use Baidu detection.
            baiduDetect(
                queryText: queryText,
                fallbackLanguage: fallbackLanguage,
                fallbackError: fallbackError,
                completion: completion
            )
        }
    }
}

// MARK: - DetectManager + Async

extension DetectManager {
    /// Asynchronously detects the language of the given text.
    /// - Parameter text: The text to detect language of.
    /// - Returns: The query model with detected language set.
    @nonobjc
    public func detectText(_ text: String) async throws -> QueryModel {
        try await withCheckedThrowingContinuation { continuation in
            detectText(text) { queryModel, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: queryModel)
                }
            }
        }
    }
}
