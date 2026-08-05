//
//  QueryLanguageMigrationTests.swift
//  EasydictTests
//
//  Created by TheQY71 on 2026/8/5.
//  Copyright © 2026 izual. All rights reserved.
//

import Defaults
import Foundation
import Testing

@testable import Easydict

// MARK: - QueryLanguageMigrationTests

/// Verifies one-time restoration of automatic query language selection. Each
/// scenario snapshots the exact persisted values for every touched preference
/// and restores them after the migration assertions finish.
@Suite("Query Language Migration", .serialized, .tags(.unit))
struct QueryLanguageMigrationTests {
    // MARK: Internal

    @Test("Automatic source restores a fixed target and records completion")
    func restoresFixedTarget() {
        withPreferences(from: .auto, to: .simplifiedChinese, marker: false) {
            QueryLanguageMigration.restoreAutomaticPairIfNeeded()

            #expect(Defaults[.queryFromLanguage] == .auto)
            #expect(Defaults[.queryToLanguage] == .auto)
            #expect(Defaults[.restoredAutoQueryLanguages])
        }
    }

    @Test("Completion marker preserves a later fixed target")
    func markerPreservesTarget() {
        withPreferences(from: .auto, to: .simplifiedChinese, marker: false) {
            QueryLanguageMigration.restoreAutomaticPairIfNeeded()
            Defaults[.queryToLanguage] = .english

            QueryLanguageMigration.restoreAutomaticPairIfNeeded()

            #expect(Defaults[.queryFromLanguage] == .auto)
            #expect(Defaults[.queryToLanguage] == .english)
            #expect(Defaults[.restoredAutoQueryLanguages])
        }
    }

    @Test("Already automatic pair only records completion")
    func automaticPair() {
        withPreferences(from: .auto, to: .auto, marker: false) {
            QueryLanguageMigration.restoreAutomaticPairIfNeeded()

            #expect(Defaults[.queryFromLanguage] == .auto)
            #expect(Defaults[.queryToLanguage] == .auto)
            #expect(Defaults[.restoredAutoQueryLanguages])
        }
    }

    @Test(
        "Other fixed language choices stay unchanged",
        arguments: [
            (Language.english, Language.simplifiedChinese),
            (Language.auto, Language.english),
        ]
    )
    func preservesOtherFixedChoices(from: Language, to: Language) {
        withPreferences(from: from, to: to, marker: false) {
            QueryLanguageMigration.restoreAutomaticPairIfNeeded()

            #expect(Defaults[.queryFromLanguage] == from)
            #expect(Defaults[.queryToLanguage] == to)
            #expect(Defaults[.restoredAutoQueryLanguages])
        }
    }

    // MARK: Private

    /// Runs a migration scenario while preserving the exact persisted state.
    private func withPreferences(
        from: Language,
        to: Language,
        marker: Bool,
        _ body: () -> ()
    ) {
        let defaults = UserDefaults.standard
        let keyNames = [
            Defaults.Keys.queryFromLanguage.name,
            Defaults.Keys.queryToLanguage.name,
            Defaults.Keys.restoredAutoQueryLanguages.name,
        ]
        guard let bundleID = Bundle.main.bundleIdentifier else {
            Issue.record("The test host has no bundle identifier")
            return
        }
        let persisted = defaults.persistentDomain(forName: bundleID) ?? [:]
        let snapshot = persisted.filter { keyNames.contains($0.key) }

        defer {
            keyNames.forEach(defaults.removeObject(forKey:))
            snapshot.forEach { defaults.set($0.value, forKey: $0.key) }
        }

        Defaults[.queryFromLanguage] = from
        Defaults[.queryToLanguage] = to
        Defaults[.restoredAutoQueryLanguages] = marker
        body()
    }
}
