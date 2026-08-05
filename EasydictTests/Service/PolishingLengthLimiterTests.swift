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
}
