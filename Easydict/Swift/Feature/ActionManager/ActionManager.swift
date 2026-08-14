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

    /// Result of collecting and applying one streamed replacement.
    private enum ReplacementOutcome {
        case replaced
        case unconfirmed
        case noContent
        case targetChanged
        case cannotReplace
        case invalidOutput
        case cancelled
        case failed
    }

    /// Immutable target state carried from capture through final replacement.
    private struct ReplacementContext {
        let elementInfo: FocusedElementInfo
        let sourceText: String
        let bundleID: String
        let processID: pid_t
        let type: ProcessingType
    }

    private let systemUtility = SystemUtility.shared
    private var activeProcessingType: ProcessingType?

    // MARK: - Core Action Methods

    /// Common method to execute text replacement actions. Only one replacement
    /// may run at a time so repeated shortcut events cannot start parallel streams.
    @MainActor
    private func executeTextReplacementAction(_ type: ProcessingType) async {
        guard activeProcessingType == nil else {
            logInfo("Text replacement is already running; ignore repeated \(type) action")
            if type == .polish {
                if activeProcessingType == .polish {
                    PolishingStatusHUD.shared.showProcessing()
                } else {
                    PolishingStatusHUD.shared.showError(
                        "action.polish_and_replace.error.busy"
                    )
                }
            }
            return
        }
        activeProcessingType = type
        defer { activeProcessingType = nil }

        let targetApp = NSWorkspace.shared.frontmostApplication
        let targetBundleID = targetApp?.bundleIdentifier ?? ""
        let targetProcessID = targetApp?.processIdentifier
        guard !targetBundleID.isEmpty,
              targetBundleID != Bundle.main.bundleIdentifier,
              let targetProcessID
        else {
            logInfo("Frontmost app is Easydict itself, skipping \(type)")
            showPolishingError(
                "action.polish_and_replace.error.target_unavailable",
                for: type
            )
            return
        }

        if type == .polish {
            guard !polishService.apiKey.trim().isEmpty else {
                PolishingStatusHUD.shared.showError(
                    "action.polish_and_replace.error.missing_api_key"
                )
                return
            }
            PolishingStatusHUD.shared.showProcessing()
        }

        let enableSelectAll = type == .translate
            && Defaults[.autoSelectAllTextFieldText]
        let elementInfo = await replacementTargetInfo(
            enableSelectAll: enableSelectAll,
            for: type
        )

        guard isFrontmostTarget(
            bundleID: targetBundleID,
            processID: targetProcessID
        ) else {
            logInfo("Target application changed while capturing selected text")
            showPolishingError(
                "action.polish_and_replace.error.target_changed",
                for: type
            )
            return
        }

        if type == .polish, elementInfo.element == nil {
            logInfo("No stable Accessibility target is available for polishing")
            showPolishingError(
                "action.polish_and_replace.error.target_unavailable",
                for: type
            )
            return
        }

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
            showPolishingError("action.polish_and_replace.error.no_selection", for: type)
            return
        }

        if type == .polish,
           elementInfo.selectedRange?.length ?? 0 <= 0 {
            logInfo("No stable selected range is available for polishing")
            showPolishingError(
                "action.polish_and_replace.error.target_unavailable",
                for: type
            )
            return
        }

        // Prepare translation request
        guard let request = await prepareTranslationRequest(queryText: queryText, type: type) else {
            showPolishingError("action.polish_and_replace.error.failed", for: type)
            return
        }

        guard isFrontmostTarget(
            bundleID: targetBundleID,
            processID: targetProcessID
        ) else {
            logInfo("Target application changed before the request started")
            showPolishingError(
                "action.polish_and_replace.error.target_changed",
                for: type
            )
            return
        }

        // Execute the streaming service
        let context = ReplacementContext(
            elementInfo: elementInfo,
            sourceText: queryText,
            bundleID: targetBundleID,
            processID: targetProcessID,
            type: type
        )
        let outcome = await performStreamingService(
            request: request,
            context: context
        )
        showPolishingOutcome(outcome, for: type)
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
    @MainActor
    private func performStreamingService(
        request: TranslationRequest,
        context: ReplacementContext
    ) async
        -> ReplacementOutcome {
        guard let service = QueryServiceFactory.shared.service(withTypeId: request.serviceType)
        else {
            logError("Service type \(request.serviceType) not found")
            return .failed
        }

        guard let streamService = service as? StreamService else {
            logError("\(service.name()) does not support streaming")
            return .failed
        }

        logInfo("Using model: \(streamService.model)")

        do {
            try Task.checkCancellation()
            let contentStream = try await streamService.contentStreamTranslate(request: request)
            try Task.checkCancellation()
            return try await replaceTextWithStream(
                contentStream,
                context: context
            )
        } catch is PolishingOutputError {
            logError("Polishing stopped because the model output was invalid")
            return .invalidOutput
        } catch {
            if Task.isCancelled {
                logInfo("Streaming task cancelled")
                return .cancelled
            } else {
                logError("stream failed: \(error.localizedDescription)")
                return .failed
            }
        }
    }

    /// Collects the stream and replaces the selected text once it completes.
    /// Keeping the original selection intact prevents partial or degenerate
    /// model output from being typed into the target application chunk by chunk.
    @MainActor
    private func replaceTextWithStream(
        _ contentStream: AsyncThrowingStream<String, Error>,
        context: ReplacementContext
    ) async throws
        -> ReplacementOutcome {
        logInfo("Collecting streaming content before replacing text")

        var result = ""
        for try await content in contentStream where !content.isEmpty {
            result += content
        }

        guard !result.isEmpty else {
            logInfo("Streaming replacement returned no content")
            return .noContent
        }

        guard isFrontmostTarget(
            bundleID: context.bundleID,
            processID: context.processID
        ) else {
            logInfo("Target application changed while streaming; preserve original text")
            return .targetChanged
        }

        let currentElementInfo = await replacementTargetInfo(
            for: context.type
        )
        guard isSameReplacementTarget(
            original: context.elementInfo,
            current: currentElementInfo,
            sourceText: context.sourceText,
            requiresStableTarget: context.type == .polish
        ) else {
            logInfo("Target selection changed while streaming; preserve original text")
            return .targetChanged
        }

        guard isFrontmostTarget(
            bundleID: context.bundleID,
            processID: context.processID
        ) else {
            logInfo("Target application changed before insertion; preserve original text")
            return .targetChanged
        }

        let textStrategies = systemUtility.textStrategies(for: currentElementInfo)
        let insertionResult = await systemUtility.insertText(result, using: textStrategies)

        switch insertionResult {
        case .confirmed:
            logInfo("Final replacement completed with \(result.count) characters")
            return .replaced
        case .attempted:
            logInfo("Final replacement was attempted but could not be confirmed")
            return .unconfirmed
        case .unavailable:
            logError("No text insertion strategy was available")
            return .cannotReplace
        }
    }

    /// Captures the text target without using copy-based selection for polishing.
    /// A copy fallback cannot prove that the same selection still owns focus.
    @MainActor
    private func replacementTargetInfo(
        enableSelectAll: Bool = false,
        for type: ProcessingType
    ) async
        -> FocusedElementInfo {
        await systemUtility.focusedElementInfo(
            enableSelectAll: enableSelectAll,
            safeSelectionOnly: type == .polish
        )
    }

    @MainActor
    private func showPolishingOutcome(
        _ outcome: ReplacementOutcome,
        for type: ProcessingType
    ) {
        guard type == .polish else { return }
        switch outcome {
        case .replaced:
            PolishingStatusHUD.shared.showSuccess()
        case .unconfirmed:
            PolishingStatusHUD.shared.showError(
                "action.polish_and_replace.notice.unconfirmed"
            )
        case .targetChanged:
            PolishingStatusHUD.shared.showError(
                "action.polish_and_replace.error.target_changed"
            )
        case .cannotReplace:
            PolishingStatusHUD.shared.showError(
                "action.polish_and_replace.error.cannot_replace"
            )
        case .invalidOutput:
            PolishingStatusHUD.shared.showError(
                "action.polish_and_replace.error.invalid_output"
            )
        case .cancelled:
            PolishingStatusHUD.shared.showError(
                "action.polish_and_replace.error.cancelled"
            )
        case .failed, .noContent:
            PolishingStatusHUD.shared.showError(
                "action.polish_and_replace.error.failed"
            )
        }
    }

    @MainActor
    private func showPolishingError(
        _ message: LocalizedStringResource,
        for type: ProcessingType
    ) {
        guard type == .polish else { return }
        PolishingStatusHUD.shared.showError(message)
    }

    /// Confirms that the focused text and any meaningful AX selection are the
    /// same target captured before the network request started.
    private func isSameReplacementTarget(
        original: FocusedElementInfo,
        current: FocusedElementInfo,
        sourceText: String,
        requiresStableTarget: Bool
    )
        -> Bool {
        if requiresStableTarget {
            guard let originalProcessID = original.processID,
                  current.processID == originalProcessID,
                  let originalElement = original.element,
                  current.element == originalElement
            else {
                return false
            }
        }
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

    private func isFrontmostTarget(bundleID: String, processID: pid_t) -> Bool {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.bundleIdentifier == bundleID
            && app?.processIdentifier == processID
    }
}
