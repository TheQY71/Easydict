//
//  QuickChatViewModel.swift
//  Easydict
//
//  Created by TheQY71 on 2026/08/04.
//  Copyright © 2026 izual. All rights reserved.
//

import Defaults
import Foundation

/// Drives one-shot questions to a configured LLM service.
///
/// Each send is independent: there is no conversation history, and a fresh
/// service instance is created per question so a previous answer can never
/// leak into the next one. The question is injected through
/// `StreamService.chatMessagesOverride`, which bypasses the translation
/// prompts every service would otherwise build.
@MainActor
final class QuickChatViewModel: ObservableObject {
    // MARK: Internal

    @Published var question = ""
    /// Answer text published for display. Updated on a throttle while streaming so
    /// Markdown is not re-rendered once per token.
    @Published private(set) var answer = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?

    /// Whether the current input can be sent.
    var canSend: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    /// Sends the current question and streams the answer into `answer`.
    func send() {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else { return }

        cancel()
        clearAnswer()
        errorMessage = nil

        guard let service = makeService(for: prompt) else {
            errorMessage = String(localized: "quick_chat.error.service_unavailable")
            return
        }

        self.service = service
        service.chatMessagesOverride = [
            .init(role: .system, content: Self.brevitySystemPrompt),
            .init(role: .user, content: prompt),
        ]
        isStreaming = true

        let stream = service.contentStreamTranslate(prompt, from: .auto, to: .auto)
        streamTask = Task { [weak self] in
            do {
                for try await delta in stream {
                    guard !Task.isCancelled else { return }
                    self?.append(delta)
                }
            } catch is CancellationError {
                // User-initiated stop; keep whatever text already arrived.
            } catch {
                // Some endpoints emit a trailing chunk the SSE decoder rejects
                // ("未能读取数据…"). If an answer already arrived it is complete and
                // usable, so surface the failure only when there is nothing to show.
                if self?.pendingAnswer.isEmpty ?? true {
                    self?.errorMessage = error.localizedDescription
                } else {
                    logError("Quick chat stream ended with error after content: \(error)")
                }
            }
            // The throttle may still be holding the tail of the answer.
            self?.flushPendingAnswer()
            self?.isStreaming = false
        }
    }

    /// Copies the raw Markdown answer to the pasteboard.
    func copyAnswer() {
        answer.copyToPasteboard()
    }

    /// Stops an in-flight answer without clearing what has already arrived.
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        service?.cancelStream()
        service = nil
        flushPendingAnswer()
        isStreaming = false
    }

    /// Clears the question and answer, ready for a new one-shot query.
    func reset() {
        cancel()
        question = ""
        clearAnswer()
        errorMessage = nil
    }

    // MARK: Private

    /// Keeps answers short at the source, so the panel is not filled with text the
    /// display would only have to collapse again.
    private static let brevitySystemPrompt = """
    You are answering inside a small quick-lookup panel, so keep it short.
    Lead with the direct answer in a few sentences and stop there, unless the \
    question genuinely needs more.
    Skip preambles, restatements of the question, and closing summaries.
    Reply in the same language as the question.
    Use Markdown only where it aids clarity, such as a short list or inline code.
    """

    private var streamTask: Task<(), Never>?
    private var service: StreamService?

    /// Full answer received so far; `answer` catches up to it on the throttle.
    private var pendingAnswer = ""

    /// 0.2s is the floor `Throttler` documents for UI updates; anything faster
    /// re-renders the Markdown often enough to spike CPU on long answers.
    private let answerThrottler = Throttler(maxInterval: 0.2)

    /// Buffers a streamed delta and schedules a throttled publish.
    private func append(_ delta: String) {
        pendingAnswer += delta
        answerThrottler.throttle {
            Task { @MainActor [weak self] in
                self?.flushPendingAnswer()
            }
        }
    }

    /// Publishes any buffered text the throttle has not delivered yet.
    private func flushPendingAnswer() {
        guard answer != pendingAnswer else { return }
        answer = pendingAnswer
    }

    private func clearAnswer() {
        pendingAnswer = ""
        answer = ""
    }

    private func streamService(for typeID: String) -> StreamService? {
        QueryServiceFactory.shared.service(withTypeId: typeID) as? StreamService
    }

    /// Builds the service selected in settings, or `nil` when it is not a stream service.
    ///
    /// `contentStreamTranslate` is normally reached through the query pipeline, which
    /// seeds `queryModel` and `result` first. Quick chat calls it directly, and services
    /// such as `BaseOpenAIService` immediately touch `result` — an implicitly unwrapped
    /// optional — so both are prepared here.
    private func makeService(for prompt: String) -> StreamService? {
        guard let service = streamService(for: Defaults[.quickChatServiceType]) else {
            return nil
        }

        let model = QueryModel()
        model.inputText = prompt
        service.queryModel = model

        let result = QueryResult()
        result.queryText = prompt
        result.from = .auto
        result.to = .auto
        service.result = result

        return service
    }
}
