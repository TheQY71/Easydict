//
//  PolishingLengthLimiterTests.swift
//  EasydictTests
//
//  Created by TheQY71 on 2026/4/5.
//  Copyright © 2026 izual. All rights reserved.
//

import Testing

@testable import Easydict

// MARK: - PolishingLengthLimiterTests

/// Verifies that streamed polishing output stays within its character budget.
/// Coverage includes integer rounding, cumulative chunks, exhausted budgets,
/// and extended grapheme clusters.
@Suite("Polishing Length Limiter", .tags(.unit))
struct PolishingLengthLimiterTests {
    @Test("Even source length allows the default 200 percent")
    func evenSourceLengthAllowsDoubleLimit() {
        var limiter = PolishingLengthLimiter(sourceLength: 4, ratioPercent: 200)

        let output = limiter.limit("abcdefghi")

        #expect(limiter.maxLength == 8)
        #expect(output == "abcdefgh")
        #expect(output.count == 8)
        #expect(limiter.hasReachedLimit)
    }

    @Test("Odd source length allows the default 200 percent")
    func oddSourceLengthAllowsDoubleLimit() {
        var limiter = PolishingLengthLimiter(sourceLength: 5, ratioPercent: 200)

        let output = limiter.limit("abcdefghijk")

        #expect(limiter.maxLength == 10)
        #expect(output == "abcdefghij")
        #expect(output.count == 10)
        #expect(limiter.hasReachedLimit)
    }

    @Test("Odd source length rounds 150 percent down")
    func oddSourceLengthRoundsOneAndHalfDown() {
        var limiter = PolishingLengthLimiter(sourceLength: 5, ratioPercent: 150)

        let output = limiter.limit("abcdefgh")

        #expect(limiter.maxLength == 7)
        #expect(output == "abcdefg")
        #expect(output.count * 2 <= 5 * 3)
        #expect(limiter.hasReachedLimit)
    }

    @Test("Chunks share one 200 percent budget and the final chunk is truncated")
    func chunksShareDoubleBudget() {
        var limiter = PolishingLengthLimiter(sourceLength: 6, ratioPercent: 200)

        let first = limiter.limit("abc")
        let second = limiter.limit("defg")
        let final = limiter.limit("hijklmnop")

        #expect(first == "abc")
        #expect(second == "defg")
        #expect(final == "hijkl")
        #expect((first + second + final).count == 12)
        #expect(limiter.emittedLength == limiter.maxLength)
    }

    @Test("Chunks after the 200 percent limit return empty output")
    func chunksAfterDoubleLimitAreEmpty() {
        var limiter = PolishingLengthLimiter(sourceLength: 2, ratioPercent: 200)

        #expect(limiter.limit("abcd") == "abcd")
        #expect(limiter.hasReachedLimit)
        #expect(limiter.limit("ef") == "")
        #expect(limiter.emittedLength == 4)
    }

    @Test("Unicode characters remain whole at the 200 percent limit")
    func graphemeClustersRemainWhole() {
        let source = "👨‍👩‍👧‍👦e\u{301}"
        let family = "👨‍👩‍👧‍👦"
        let accentedE = "e\u{301}"
        let thumbsUp = "👍🏽"
        let flag = "🇨🇳"
        var limiter = PolishingLengthLimiter(
            sourceLength: source.count,
            ratioPercent: 200
        )

        let output = limiter.limit(family + accentedE + thumbsUp + flag + "Z")

        #expect(source.count == 2)
        #expect(limiter.maxLength == 4)
        #expect(output == family + accentedE + thumbsUp + flag)
        #expect(output.count == 4)
        #expect(limiter.emittedLength == 4)
    }

    @Test(
        "Six single letters or Chinese characters stop at the loop start",
        arguments: ["a", "哈"]
    )
    func singleCharacterLoopsStopAtStart(character: String) {
        let prefix = "Polished: "
        var outputGuard = PolishingOutputGuard(
            sourceLength: 200,
            ratioPercent: 100
        )

        let decision = outputGuard.consume(
            prefix + String(repeating: character, count: 6)
        )

        #expect(decision.content == prefix)
        #expect(decision.stopReason == .repetition)
        #expect(outputGuard.acceptedText == prefix)
    }

    @Test(
        "Two to four character patterns stop after four repeats",
        arguments: ["ab", "xyz", "WXYZ"]
    )
    func shortPatternsStopAfterFourRepeats(pattern: String) {
        let prefix = "Polished: "
        var outputGuard = PolishingOutputGuard(
            sourceLength: 200,
            ratioPercent: 100
        )

        let decision = outputGuard.consume(
            prefix + String(repeating: pattern, count: 4)
        )

        #expect(decision.content == prefix)
        #expect(decision.stopReason == .repetition)
        #expect(outputGuard.acceptedText == prefix)
    }

    @Test(
        "Patterns of five or more characters stop after three repeats",
        arguments: ["abcde", "polished"]
    )
    func longPatternsStopAfterThreeRepeats(pattern: String) {
        let prefix = "Polished: "
        var outputGuard = PolishingOutputGuard(
            sourceLength: 200,
            ratioPercent: 100
        )

        let decision = outputGuard.consume(
            prefix + String(repeating: pattern, count: 3)
        )

        #expect(decision.content == prefix)
        #expect(decision.stopReason == .repetition)
        #expect(outputGuard.acceptedText == prefix)
    }

    @Test("A repetition loop spanning chunks is detected")
    func loopSpanningChunksStops() {
        var outputGuard = PolishingOutputGuard(
            sourceLength: 200,
            ratioPercent: 100
        )

        let first = outputGuard.consume("Polished: ca")
        let second = outputGuard.consume("tcatc")
        let final = outputGuard.consume("atcat")

        #expect(first.content == "Polished: ca")
        #expect(first.stopReason == nil)
        #expect(second.content == "tcatc")
        #expect(second.stopReason == nil)
        #expect(final.content.isEmpty)
        #expect(final.stopReason == .repetition)
    }

    @Test(
        "Natural language with limited repetition does not stop",
        arguments: [
            "The result remains very very",
            "这个结果让人觉得哈哈哈",
        ]
    )
    func naturalRepetitionDoesNotStop(content: String) {
        var outputGuard = PolishingOutputGuard(
            sourceLength: 200,
            ratioPercent: 100
        )

        let decision = outputGuard.consume(content)

        #expect(decision.content == content)
        #expect(decision.stopReason == nil)
        #expect(outputGuard.acceptedText == content)
    }

    @Test(
        "Punctuation and Markdown separators do not stop",
        arguments: [
            "----------------",
            "****************",
            "________________",
            "\n---\n---\n---\n---\n",
        ]
    )
    func punctuationDoesNotStop(content: String) {
        var outputGuard = PolishingOutputGuard(
            sourceLength: 200,
            ratioPercent: 100
        )

        let decision = outputGuard.consume(content)

        #expect(decision.content == content)
        #expect(decision.stopReason == nil)
        #expect(outputGuard.acceptedText == content)
    }

    @Test("Shuffled screenshot text spanning chunks is rejected")
    func shuffledScreenshotTextStops() {
        let ocrChunks = [
            "请简要总结论文：论文论文arxiv.org请/pdf简要/260这篇6论文6：290https13://13请13简要/pdf总结/",
            "这篇请请请请请简要请httpshttps请https://这篇https290arxiv论文论文请13.org",
            "请请：总结/pdf简要简要httpshttps/：//：//：//论文13这篇这篇arxiv：6请1313httpsH",
            "T.帮我/pdf/pdfarxiv://TPS/pdf总结/arxivarxivarxiv13这篇260260260.org论文66/pdf请请请",
        ]
        var outputGuard = PolishingOutputGuard(
            sourceLength: 10_000,
            ratioPercent: 100
        )

        let first = outputGuard.consume(ocrChunks[0])
        let second = outputGuard.consume(ocrChunks[1])
        let trigger = outputGuard.consume(ocrChunks[2])
        let acceptedPrefix = ocrChunks[0] + ocrChunks[1]
        let consumedLength = ocrChunks[0 ... 2].joined().count

        #expect(ocrChunks.joined().count == 253)
        #expect(consumedLength <= 250)
        #expect(first.content == ocrChunks[0])
        #expect(first.stopReason == nil)
        #expect(second.content == ocrChunks[1])
        #expect(second.stopReason == nil)
        #expect(trigger.content.isEmpty)
        #expect(trigger.stopReason == .repetition)
        #expect(outputGuard.acceptedText == acceptedPrefix)
        #expect(!outputGuard.acceptedText.contains(ocrChunks[2]))
    }

    @Test("A long natural Chinese paragraph is accepted")
    func naturalChineseParagraphIsAccepted() {
        let content = """
        清晨的社区图书馆刚刚开门，管理员先检查阅览室的照明和通风，再把昨夜归还的书籍按照编号放回书架。
        窗边几位学生讨论城市河流的生态调查，他们比较不同季节的水质记录，也认真标注采样地点与天气变化。
        午后，一位老人带着孙女参加手工活动，孩子用彩纸制作候鸟模型，并在地图上寻找迁徙路线。
        傍晚闭馆前，志愿者整理桌椅、回收废纸，还为第二天的科普讲座调试投影设备。
        整个空间安静而有活力，每个人都能按自己的节奏阅读、交流和学习。
        """
        var outputGuard = PolishingOutputGuard(
            sourceLength: 10_000,
            ratioPercent: 100
        )

        let decision = outputGuard.consume(content)

        #expect(content.count >= 120)
        #expect(decision.content == content)
        #expect(decision.stopReason == nil)
        #expect(outputGuard.acceptedText == content)
    }

    @Test("A long natural English paragraph is accepted")
    func naturalEnglishParagraphIsAccepted() {
        let content = """
        Before sunrise, the research team checked every sensor beside the wetland
        trail and recorded the battery level in a shared notebook. Later, two
        volunteers photographed fresh animal tracks, compared them with last week's
        observations, and marked each location on a paper map. The afternoon briefing
        focused on water quality, changing vegetation, and safe routes for the next
        survey. By dusk, everyone had cleaned the equipment, backed up the images, and
        written a concise field report for the park staff.
        """
        var outputGuard = PolishingOutputGuard(
            sourceLength: 10_000,
            ratioPercent: 100
        )

        let decision = outputGuard.consume(content)

        #expect(content.count >= 160)
        #expect(decision.content == content)
        #expect(decision.stopReason == nil)
        #expect(outputGuard.acceptedText == content)
    }

    @Test("Code with repeated for and append structures is accepted")
    func repeatedCodeStructuresAreAccepted() {
        let content = """
        var rows: [String] = []
        for section in sections {
            var values: [String] = []
            for item in section.items {
                values.append(item.displayName)
            }
            rows.append(values.joined(separator: ", "))
        }
        for warning in warnings {
            var details: [String] = []
            for message in warning.messages {
                details.append(message.localizedDescription)
            }
            rows.append(details.joined(separator: " | "))
        }
        return rows
        """
        var outputGuard = PolishingOutputGuard(
            sourceLength: 10_000,
            ratioPercent: 100
        )

        let decision = outputGuard.consume(content)

        #expect(content.count >= 120)
        #expect(decision.content == content)
        #expect(decision.stopReason == nil)
        #expect(outputGuard.acceptedText == content)
    }

    @Test("The output guard preserves graphemes at its length limit")
    func outputGuardPreservesGraphemes() {
        let family = "👨‍👩‍👧‍👦"
        let accentedE = "e\u{301}"
        let thumbsUp = "👍🏽"
        let flag = "🇨🇳"
        let expected = family + accentedE + thumbsUp + flag
        var outputGuard = PolishingOutputGuard(
            sourceLength: 2,
            ratioPercent: 200
        )

        let decision = outputGuard.consume(expected + "Z")
        let afterLimit = outputGuard.consume("extra")

        #expect(decision.content == expected)
        #expect(decision.content.count == 4)
        #expect(decision.stopReason == .lengthLimit)
        #expect(outputGuard.acceptedText == expected)
        #expect(afterLimit.content.isEmpty)
        #expect(afterLimit.stopReason == .lengthLimit)
    }
}
