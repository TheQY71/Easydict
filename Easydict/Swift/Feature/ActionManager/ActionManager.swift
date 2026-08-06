//
//  ActionManager.swift
//  Easydict
//
//  Created by tisfeng on 2025/8/29.
//  Copyright © 2025 izual. All rights reserved.
//

import AppKit
import Defaults
import Foundation
import SelectedTextKit

// MARK: - ActionManager

/// Singleton class responsible for handling various application actions
@objc(EZActionManager)
class ActionManager: NSObject {
    // MARK: Internal

    // MARK: - Singleton

    @objc static let shared = ActionManager()

    var translateService = DeepSeekService()
    var polishService = PolishingService()

    // MARK: - Text Field Detection and Access

    // MARK: - Public Methods

    /// Translate selected text and replace it with the translation result
    func translateAndReplace() async {
        logInfo("Translate and Replace")
        await executeTextReplacementAction(.translate)
    }

    /// Polish selected text and replace it with the polished result
    func polishAndReplace() async {
        logInfo("Polish and Replace")
        await executeTextReplacementAction(.polish)
    }

    // MARK: Private

    /// Type of text processing action
    private enum ProcessingType {
        case translate
        case polish
    }

    private let systemUtility = SystemUtility.shared
    private var isReplacingText = false

    // MARK: - Core Action Methods

    /// Common method to execute text replacement actions. Only one replacement
    /// may run at a time so repeated shortcut events cannot start parallel streams.
    @MainActor
    private func executeTextReplacementAction(_ type: ProcessingType) async {
        guard !isReplacingText else {
            logInfo("Text replacement is already running; ignore repeated \(type) action")
            return
        }
        isReplacingText = true
        defer { isReplacingText = false }

        let targetBundleID = frontmostAppBundleID
        guard targetBundleID != Bundle.main.bundleIdentifier else {
            logInfo("Frontmost app is Easydict itself, skipping \(type)")
            return
        }

        let enableSelectAll = type == .translate
            && Defaults[.autoSelectAllTextFieldText]
        let elementInfo = await systemUtility.focusedElementInfo(
            enableSelectAll: enableSelectAll
        )

        let queryText: String?
        switch type {
        case .translate:
            var text = elementInfo.focusedText
            if text?.isEmpty ?? true {
                text = await systemUtility.getSelectedText()
            }
            queryText = text
        case .polish:
            queryText = elementInfo.selectedText
        }

        guard let queryText, !queryText.isEmpty else {
            logInfo("No text selected for \(type), skipping action")
            return
        }

        // Prepare translation request
        guard let request = await prepareTranslationRequest(queryText: queryText, type: type) else {
            return
        }

        // Execute the streaming service
        await performStreamingService(
            request: request,
            elementInfo: elementInfo,
            sourceText: queryText,
            targetBundleID: targetBundleID
        )
    }

    // MARK: - Helper Methods

    /// Prepare translation request from text field information
    /// - Parameters:
    ///   - queryText: Source text to process.
    ///   - type: The type of processing (translate or polish)
    /// - Returns: A configured TranslationRequest or nil if preparation fails
    private func prepareTranslationRequest(
        queryText: String,
        type: ProcessingType
    ) async
        -> TranslationRequest? {
        // Detect language and target
        let queryModel = try? await DetectManager().detectText(queryText)
        guard let detectedLanguage = queryModel?.detectedLanguage,
              let targetLanguage = queryModel?.queryTargetLanguage
        else {
            logError("Failed to detect target language, skipping \(type) and replace")
            return nil
        }

        // Create base request
        var request = TranslationRequest(
            text: queryText,
            sourceLanguage: detectedLanguage.code,
            targetLanguage: targetLanguage.code,
            serviceType: "",
            queryType: .translation
        )

        // Set service type based on processing type
        switch type {
        case .translate:
            request.serviceType = translateService.serviceType().rawValue
        case .polish:
            request.serviceType = polishService.serviceType().rawValue
        }

        return request
    }

    // MARK: - Streaming Service Methods

    /// Perform translation or polishing using a streaming service
    private func performStreamingService(
        request: TranslationRequest,
        elementInfo: FocusedElementInfo,
        sourceText: String,
        targetBundleID: String
    ) async {
        guard let service = QueryServiceFactory.shared.service(withTypeId: request.serviceType)
        else {
            logError("Service type \(request.serviceType) not found")
            return
        }

        guard let streamService = service as? StreamService else {
            logError("\(service.name()) does not support streaming")
            return
        }

        logInfo("Using model: \(streamService.model)")

        do {
            try Task.checkCancellation()
            let contentStream = try await streamService.contentStreamTranslate(request: request)
            try Task.checkCancellation()
            await replaceTextWithStream(
                contentStream,
                elementInfo: elementInfo,
                sourceText: sourceText,
                targetBundleID: targetBundleID
            )
        } catch {
            if Task.isCancelled {
                logInfo("Streaming task cancelled")
            } else {
                logError("stream failed: \(error.localizedDescription)")
            }
        }
    }

    /// Collects the stream and replaces the selected text once it completes.
    /// Keeping the original selection intact prevents partial or degenerate
    /// model output from being typed into the target application chunk by chunk.
    @MainActor
    private func replaceTextWithStream(
        _ contentStream: AsyncThrowingStream<String, Error>,
        elementInfo: FocusedElementInfo,
        sourceText: String,
        targetBundleID: String
    ) async {
        logInfo("Collecting streaming content before replacing text")

        do {
            var result = ""
            for try await content in contentStream where !content.isEmpty {
                result += content
            }

            guard !result.isEmpty else {
                logInfo("Streaming replacement returned no content")
                return
            }

            guard frontmostAppBundleID == targetBundleID else {
                logInfo("Target application changed while streaming; preserve original text")
                return
            }

            let currentElementInfo = await systemUtility.focusedElementInfo()
            guard isSameReplacementTarget(
                original: elementInfo,
                current: currentElementInfo,
                sourceText: sourceText
            ) else {
                logInfo("Target selection changed while streaming; preserve original text")
                return
            }

            let textStrategies = systemUtility.textStrategies(for: elementInfo)
            let pasteboard = NSPasteboard.general
            let snapshotItems = elementInfo.isSupportedAXElement ? nil : pasteboard.backupItems()

            await systemUtility.insertText(result, using: textStrategies)

            if let snapshotItems {
                pasteboard.restoreItems(snapshotItems)
            }
            logInfo("Final replacement result: \(result.prettyJSONString)")
        } catch {
            logError("Streaming replacement failed without changing original text: \(error)")
        }
    }

    /// Confirms that the focused text and any meaningful AX selection are the
    /// same target captured before the network request started.
    private func isSameReplacementTarget(
        original: FocusedElementInfo,
        current: FocusedElementInfo,
        sourceText: String
    )
        -> Bool {
        guard current.focusedText == sourceText else { return false }
        guard let originalRange = original.selectedRange,
              originalRange.length > 0
        else {
            return true
        }
        guard let currentRange = current.selectedRange else { return false }
        return originalRange.location == currentRange.location
            && originalRange.length == currentRange.length
    }
}
