//
//  LocalStorageMigrationTests.swift
//  EasydictTests
//
//  Created by TheQY71 on 2026/4/5.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import Testing

@testable import Easydict

// MARK: - LocalStorageMigrationTests

/// Verifies migration from fixed, mini, and main service storage into shared
/// service order and configuration keys. Each test snapshots every touched
/// standard-defaults key and recreates the LocalStorage singleton so migration
/// behavior is exercised through normal initialization.
@Suite("Local Storage Migration", .serialized, .tags(.unit))
struct LocalStorageMigrationTests {
    // MARK: Internal

    @Test("Legacy orders merge stably without losing window-only identifiers")
    func legacyOrdersMergeStably() {
        let miniOnly = "\(ServiceType.deepSeek.rawValue)#mini-uuid"
        let mainOnly = "\(ServiceType.polishing.rawValue)#main-uuid"
        let serviceIDs = [
            ServiceType.youdao.rawValue,
            ServiceType.deepSeek.rawValue,
            ServiceType.polishing.rawValue,
            miniOnly,
            mainOnly,
        ]

        withStorageIsolation(serviceIDs: serviceIDs) { defaults in
            defaults.set(
                [ServiceType.youdao.rawValue, ServiceType.deepSeek.rawValue],
                forKey: legacyOrderKey(.fixed)
            )
            defaults.set(
                [ServiceType.deepSeek.rawValue, miniOnly],
                forKey: legacyOrderKey(.mini)
            )
            defaults.set(
                [ServiceType.polishing.rawValue, mainOnly, ServiceType.youdao.rawValue],
                forKey: legacyOrderKey(.main)
            )

            let storage = LocalStorage.shared()
            let expected = [
                ServiceType.youdao.rawValue,
                ServiceType.deepSeek.rawValue,
                miniOnly,
                ServiceType.polishing.rawValue,
                mainOnly,
            ]

            #expect(defaults.stringArray(forKey: Keys.unifiedOrder) == expected)
            #expect(storage.allServiceTypes(.fixed) == expected)
            #expect(storage.allServiceTypes(.mini) == expected)
            #expect(storage.allServiceTypes(.main) == expected)
            #expect(storage.serviceInfo(
                withType: .deepSeek,
                serviceId: "mini-uuid",
                windowType: .fixed
            )?.uuid == "mini-uuid")
            #expect(storage.serviceInfo(
                withType: .polishing,
                serviceId: "main-uuid",
                windowType: .fixed
            )?.uuid == "main-uuid")
        }
    }

    @Test("Fixed service info wins conflicts during migration")
    func fixedInfoWinsConflicts() throws {
        let serviceID = ServiceType.deepSeek.rawValue

        try withStorageIsolation(serviceIDs: [serviceID]) { defaults in
            defaults.set([serviceID], forKey: legacyOrderKey(.fixed))
            defaults.set([serviceID], forKey: legacyOrderKey(.mini))
            defaults.set([serviceID], forKey: legacyOrderKey(.main))
            try setLegacyInfo(
                serviceID: serviceID,
                windowType: .fixed,
                enabled: false,
                enabledQuery: false,
                defaults: defaults
            )
            try setLegacyInfo(
                serviceID: serviceID,
                windowType: .mini,
                enabled: true,
                enabledQuery: true,
                defaults: defaults
            )
            try setLegacyInfo(
                serviceID: serviceID,
                windowType: .main,
                enabled: true,
                enabledQuery: false,
                defaults: defaults
            )

            let info = LocalStorage.shared().serviceInfo(
                withType: .deepSeek,
                serviceId: "",
                windowType: .main
            )

            #expect(info?.enabled == false)
            #expect(info?.enabledQuery == false)
            #expect(info?.windowType == .fixed)
        }
    }

    @Test("Legacy info fills an existing unified order")
    func legacyInfoFillsExistingOrder() throws {
        let serviceID = ServiceType.deepSeek.rawValue

        try withStorageIsolation(serviceIDs: [serviceID]) { defaults in
            defaults.set([serviceID], forKey: Keys.unifiedOrder)
            defaults.set([serviceID], forKey: legacyOrderKey(.mini))
            try setLegacyInfo(
                serviceID: serviceID,
                windowType: .mini,
                enabled: false,
                enabledQuery: true,
                defaults: defaults
            )

            let info = LocalStorage.shared().serviceInfo(
                withType: .deepSeek,
                serviceId: "",
                windowType: .fixed
            )

            #expect(defaults.stringArray(forKey: Keys.unifiedOrder) == [serviceID])
            #expect(info?.enabled == false)
            #expect(info?.enabledQuery == true)
            #expect(defaults.data(forKey: unifiedInfoKey(serviceID)) != nil)
        }
    }

    @Test("Migration version makes later initialization idempotent")
    func migrationVersionMakesInitializationIdempotent() throws {
        let serviceID = ServiceType.deepSeek.rawValue
        let lateServiceID = "\(ServiceType.polishing.rawValue)#late-uuid"

        try withStorageIsolation(serviceIDs: [serviceID, lateServiceID]) { defaults in
            defaults.set([serviceID], forKey: legacyOrderKey(.fixed))
            try setLegacyInfo(
                serviceID: serviceID,
                windowType: .fixed,
                enabled: false,
                enabledQuery: false,
                defaults: defaults
            )

            let firstStorage = LocalStorage.shared()
            let firstInfo = firstStorage.serviceInfo(
                withType: .deepSeek,
                serviceId: "",
                windowType: .fixed
            )
            #expect(defaults.integer(forKey: Keys.version) == 1)
            #expect(defaults.stringArray(forKey: Keys.unifiedOrder) == [serviceID])
            #expect(firstInfo?.enabled == false)

            LocalStorage.destroySharedInstance()
            defaults.set([lateServiceID, serviceID], forKey: legacyOrderKey(.fixed))
            try setLegacyInfo(
                serviceID: serviceID,
                windowType: .fixed,
                enabled: true,
                enabledQuery: true,
                defaults: defaults
            )

            let secondInfo = LocalStorage.shared().serviceInfo(
                withType: .deepSeek,
                serviceId: "",
                windowType: .main
            )

            #expect(defaults.stringArray(forKey: Keys.unifiedOrder) == [serviceID])
            #expect(secondInfo?.enabled == false)
            #expect(secondInfo?.enabledQuery == false)
            #expect(defaults.data(forKey: unifiedInfoKey(lateServiceID)) == nil)
        }
    }

    // MARK: Private

    /// UserDefaults keys owned by unified service storage.
    private enum Keys {
        static let unifiedOrder = "kAllServiceTypesKey"
        static let version = "kUnifiedServiceStorageVersionKey"
        static let infoPrefix = "kServiceInfoStorageKey"
    }

    /// Runs one migration scenario without leaking singleton or defaults state.
    private func withStorageIsolation(
        serviceIDs: [String],
        _ body: (UserDefaults) throws -> ()
    ) rethrows {
        let defaults = UserDefaults.standard
        let keys = touchedKeys(serviceIDs: serviceIDs)
        let snapshot = keys.reduce(into: [String: Any]()) { values, key in
            values[key] = defaults.object(forKey: key)
        }

        LocalStorage.destroySharedInstance()
        keys.forEach(defaults.removeObject(forKey:))
        defer {
            LocalStorage.destroySharedInstance()
            keys.forEach(defaults.removeObject(forKey:))
            snapshot.forEach { defaults.set($0.value, forKey: $0.key) }
        }

        try body(defaults)
    }

    private func touchedKeys(serviceIDs: [String]) -> Set<String> {
        let orderKeys = Set([
            Keys.unifiedOrder,
            Keys.version,
            legacyOrderKey(.fixed),
            legacyOrderKey(.mini),
            legacyOrderKey(.main),
        ])
        let infoKeys = serviceIDs.flatMap { serviceID in
            [
                unifiedInfoKey(serviceID),
                legacyInfoKey(serviceID, windowType: .fixed),
                legacyInfoKey(serviceID, windowType: .mini),
                legacyInfoKey(serviceID, windowType: .main),
            ]
        }
        return orderKeys.union(infoKeys)
    }

    private func legacyOrderKey(_ windowType: EZWindowType) -> String {
        "\(Keys.unifiedOrder)-\(windowType.rawValue)"
    }

    private func unifiedInfoKey(_ serviceID: String) -> String {
        let components = serviceIDComponents(serviceID)
        if components.uuid.isEmpty {
            return "\(Keys.infoPrefix)-\(components.type)"
        }
        return "\(Keys.infoPrefix)-\(components.type)-\(components.uuid)"
    }

    private func legacyInfoKey(_ serviceID: String, windowType: EZWindowType) -> String {
        "\(unifiedInfoKey(serviceID))-\(windowType.rawValue)"
    }

    private func serviceIDComponents(_ serviceID: String) -> (type: String, uuid: String) {
        let components = serviceID.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        return (
            String(components.first ?? Substring(serviceID)),
            components.count > 1 ? String(components[1]) : ""
        )
    }

    /// Stores a legacy JSON payload under its old per-window key.
    private func setLegacyInfo(
        serviceID: String,
        windowType: EZWindowType,
        enabled: Bool,
        enabledQuery: Bool,
        defaults: UserDefaults
    ) throws {
        let components = serviceIDComponents(serviceID)
        let payload: [String: Any] = [
            "uuid": components.uuid,
            "type": components.type,
            "enabled": enabled,
            "enabledQuery": enabledQuery,
            "windowType": windowType.rawValue,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        defaults.set(data, forKey: legacyInfoKey(serviceID, windowType: windowType))
    }
}
