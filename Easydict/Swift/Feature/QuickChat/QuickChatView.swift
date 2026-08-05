//
//  QuickChatView.swift
//  Easydict
//
//  Created by TheQY71 on 2026/08/04.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SFSafeSymbols
import SwiftUI

// MARK: - QuickChatView

/// The quick chat panel: a question field on top, the streamed answer below.
///
/// The answer is rendered as Markdown throughout streaming. The view model
/// publishes on a throttle and the render is cached in state, so a long answer
/// re-parses a few times per second rather than once per token. Fenced code
/// blocks are split out and drawn as dedicated cards, since an attributed
/// string cannot produce a full-width padded container. The layout is
/// state-driven: idle shows a centered hint, streaming shows a progress row,
/// and errors render as a tinted callout instead of raw text.
struct QuickChatView: View {
    // MARK: Lifecycle

    init(viewModel: QuickChatViewModel) {
        self.viewModel = viewModel
    }

    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            Divider()
            answerArea
        }
        .frame(minWidth: 420, minHeight: 300)
        // The panel uses `.fullSizeContentView`; without this the hosting view
        // re-insets the content by the hidden titlebar's height.
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            isInputFocused = true
            updateRenderedAnswer()
        }
        .onChange(of: viewModel.answer) { newAnswer in
            // A cleared answer means a new question started; collapse again.
            if newAnswer.isEmpty {
                isAnswerExpanded = false
                endCopyFeedback()
            }
            updateRenderedAnswer()
        }
        .onChange(of: isAnswerExpanded) { _ in
            updateRenderedAnswer()
        }
        // The window is reused rather than recreated, so refocus on every show.
        .onReceive(
            NotificationCenter.default.publisher(
                for: QuickChatWindowController.didShowNotification
            )
        ) { _ in
            isInputFocused = true
        }
    }

    // MARK: Private

    /// A renderable piece of the answer: Markdown text already rendered to an
    /// attributed string, or a fenced code block drawn by `CodeBlockView`.
    private enum AnswerBlock {
        case text(AttributedString)
        case code(String, language: String?)
    }

    /// Characters of an answer shown before it is collapsed.
    ///
    /// Quick chat is meant to be glanced at, so a long answer is cut down rather
    /// than filling the window. Nothing is lost: the copy button and the expand
    /// button both work on the full text.
    private static let answerDisplayLimit = 600

    /// Owned by `QuickChatWindowController` so it can prefill the selected text
    /// before the window is shown.
    @ObservedObject private var viewModel: QuickChatViewModel
    @FocusState private var isInputFocused: Bool

    /// Cached render of `viewModel.answer`, split into text and code blocks.
    ///
    /// Held in state rather than recomputed in `body` so that unrelated updates —
    /// notably every keystroke in the question field — do not re-parse the whole
    /// answer.
    @State private var answerBlocks: [AnswerBlock] = []

    @State private var isAnswerExpanded = false

    /// Briefly swaps the copy icon for a checkmark after copying.
    @State private var showCopied = false
    @State private var copyResetTask: Task<(), Never>?

    private var isAnswerTruncated: Bool {
        !isAnswerExpanded && viewModel.answer.count > Self.answerDisplayLimit
    }

    /// Whether there is anything worth copying or clearing. The secondary
    /// actions stay hidden until then, keeping the idle input row minimal.
    private var hasResultContent: Bool {
        !viewModel.answer.isEmpty || viewModel.errorMessage != nil
    }

    private var showsIdlePlaceholder: Bool {
        viewModel.answer.isEmpty
            && viewModel.errorMessage == nil
            && !viewModel.isStreaming
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField(
                "quick_chat.input.placeholder",
                text: $viewModel.question,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1 ... 5)
            .font(.system(size: 13))
            .focused($isInputFocused)
            .onSubmit(viewModel.send)

            if hasResultContent {
                copyButton
                clearButton
            }

            sendOrStopButton
        }
        .animation(.easeInOut(duration: 0.15), value: hasResultContent)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var copyButton: some View {
        Button(action: copyAnswer) {
            Image(systemSymbol: showCopied ? .checkmark : .docOnDoc)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(showCopied ? Color.green : Color.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.answer.isEmpty)
        .help("quick_chat.action.copy")
        .transition(.opacity)
    }

    private var clearButton: some View {
        Button(action: clearAll) {
            Image(systemSymbol: .trash)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("quick_chat.action.clear")
        .transition(.opacity)
    }

    @ViewBuilder private var sendOrStopButton: some View {
        if viewModel.isStreaming {
            Button(action: viewModel.cancel) {
                Image(systemSymbol: .stopCircleFill)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("quick_chat.action.stop")
        } else {
            Button(action: viewModel.send) {
                Image(systemSymbol: .arrowUpCircleFill)
                    .font(.system(size: 20))
                    .foregroundStyle(
                        viewModel.canSend
                            ? Color.accentColor
                            : Color.secondary.opacity(0.5)
                    )
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .help("quick_chat.action.send")
        }
    }

    // MARK: - Answer area

    @ViewBuilder private var answerArea: some View {
        if showsIdlePlaceholder {
            idlePlaceholder
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if viewModel.isStreaming, viewModel.answer.isEmpty {
                        thinkingIndicator
                    }

                    if let errorMessage = viewModel.errorMessage {
                        errorCallout(errorMessage)
                    }

                    if !viewModel.answer.isEmpty {
                        ForEach(
                            Array(answerBlocks.enumerated()), id: \.offset
                        ) { _, block in
                            answerBlockView(block)
                        }
                    }

                    if isAnswerTruncated {
                        showAllButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemSymbol: .bubbleLeftAndBubbleRight)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.quaternary)
                .padding(.bottom, 2)
            Text("quick_chat.empty_hint")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("quick_chat.empty_hint.esc_close")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("quick_chat.state.thinking")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private var showAllButton: some View {
        Button {
            isAnswerExpanded = true
        } label: {
            HStack(spacing: 3) {
                Text("quick_chat.answer.show_all \(viewModel.answer.count)")
                Image(systemSymbol: .chevronDown)
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12))
        }
        .buttonStyle(.link)
    }

    @ViewBuilder
    private func answerBlockView(_ block: AnswerBlock) -> some View {
        switch block {
        case let .text(rendered):
            Text(rendered)
                .textSelection(.enabled)
        case let .code(code, language):
            CodeBlockView(code: code, language: language)
        }
    }

    private func errorCallout(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemSymbol: .exclamationmarkTriangleFill)
                .font(.system(size: 12))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.09))
        }
    }

    /// Copies the answer and flashes the copy button into a checkmark.
    private func copyAnswer() {
        viewModel.copyAnswer()
        withAnimation(.easeInOut(duration: 0.15)) { showCopied = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.15)) { showCopied = false }
        }
    }

    private func clearAll() {
        endCopyFeedback()
        viewModel.reset()
    }

    private func endCopyFeedback() {
        copyResetTask?.cancel()
        copyResetTask = nil
        showCopied = false
    }

    // MARK: - Rendering

    private func updateRenderedAnswer() {
        let source = isAnswerTruncated ? clipped(viewModel.answer) : viewModel.answer
        answerBlocks = MarkdownSegment.parse(source).map { segment in
            switch segment {
            case let .text(markdown):
                .text(renderAnswer(markdown))
            case let .code(code, language):
                .code(code, language: language)
            }
        }
    }

    /// Clips the answer to the display limit, preferring a line boundary so a
    /// half-written Markdown construct is not left dangling.
    private func clipped(_ text: String) -> String {
        let head = String(text.prefix(Self.answerDisplayLimit))
        guard let lastBreak = head.lastIndex(of: "\n"),
              head.distance(from: head.startIndex, to: lastBreak) > Self.answerDisplayLimit / 2
        else {
            return head + "…"
        }
        return String(head[..<lastBreak]) + "\n…"
    }

    /// Renders Markdown with the same renderer the query result views use.
    private func renderAnswer(_ markdown: String) -> AttributedString {
        guard !markdown.isEmpty else { return AttributedString() }
        let renderer = MarkdownRenderer(
            baseFont: .systemFont(ofSize: 13),
            foregroundColor: .labelColor,
            lineSpacing: 3,
            paragraphSpacing: 8
        )
        return AttributedString(renderer.render(markdown))
    }
}

// MARK: - CodeBlockView

/// A fenced code block drawn as a rounded full-width card: monospaced text on
/// a subtle tinted background, with the fence's language tag as a header.
private struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language {
                Text(verbatim: language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(verbatim: code)
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(2.5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }
}
