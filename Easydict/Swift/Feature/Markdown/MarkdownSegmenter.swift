//
//  MarkdownSegmenter.swift
//  Easydict
//
//  Created by TheQY71 on 2026/08/05.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation

/// One display block of a Markdown document: plain Markdown text, or the body
/// of a fenced code block together with the fence's language tag. Views that
/// draw code blocks as dedicated containers split the document into segments
/// first and render each kind separately.
enum MarkdownSegment: Equatable {
    case text(String)
    case code(String, language: String?)

    // MARK: Internal

    /// Splits Markdown into text and fenced-code segments.
    ///
    /// Mirrors `MarkdownRenderer`'s fence detection (a line whose trimmed
    /// prefix is "```"). Streaming-safe: an unterminated fence yields a code
    /// segment running to the end of the buffer, so a block renders as code
    /// from the moment its opening fence arrives.
    static func parse(_ markdown: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var textLines: [String] = []
        var codeLines: [String] = []
        var language: String?
        var inFence = false

        func flushText() {
            let text = textLines.joined(separator: "\n")
            textLines.removeAll()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            segments.append(.text(text))
        }

        func flushCode(terminated: Bool) {
            let code = codeLines.joined(separator: "\n")
            codeLines.removeAll()
            // Keep an empty unterminated block: its opening fence was just
            // streamed in and the content is about to follow.
            guard !code.isEmpty || !terminated else {
                language = nil
                return
            }
            segments.append(.code(code, language: language))
            language = nil
        }

        for line in markdown.components(separatedBy: "\n") {
            let stripped = line.trimmingCharacters(in: .whitespaces)

            if inFence {
                if stripped.hasPrefix("```") {
                    inFence = false
                    flushCode(terminated: true)
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if stripped.hasPrefix("```") {
                flushText()
                let tag = stripped.dropFirst(3).trimmingCharacters(in: .whitespaces)
                language = tag.isEmpty ? nil : tag
                inFence = true
                continue
            }

            textLines.append(line)
        }

        if inFence {
            flushCode(terminated: false)
        } else {
            flushText()
        }
        return segments
    }
}
