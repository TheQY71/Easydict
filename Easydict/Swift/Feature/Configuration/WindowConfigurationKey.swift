//
//  WindowConfigurationKey.swift
//  Easydict
//
//  Created by tisfeng on 2024/10/26.
//  Copyright © 2024 izual. All rights reserved.
//

import Defaults
import Foundation

/// Returns the unified Defaults key for a window-configuration flag.
///
/// Storage is shared by every query window in this fork: `windowType` is
/// accepted for call-site compatibility but no longer keys the storage.
/// Legacy per-window values are migrated once, preferring the fixed window.
func windowConfigurationKey<T: _DefaultsSerializable>(
    _ key: WindowConfigurationKey,
    windowType: EZWindowType,
    defaultValue: T
)
    -> Defaults.Key<T> {
    _ = WindowConfigurationMigration.once
    return .init("EZConfiguration_\(key.stringValue)_Key", default: defaultValue)
}

// MARK: - WindowConfigurationKey

@objc
enum WindowConfigurationKey: Int {
    case inputFieldCellVisible
    case selectLanguageCellVisible

    // MARK: Internal

    var stringValue: String {
        switch self {
        case .inputFieldCellVisible: "InputFieldCellVisible"
        case .selectLanguageCellVisible: "SelectLanguageCellVisible"
        }
    }
}

// MARK: - WindowConfigurationMigration

/// One-time copy of legacy per-window configuration values to the unified
/// keys. The fixed window's value wins, falling back to mini, then main.
private enum WindowConfigurationMigration {
    static let once: () = {
        let defaults = UserDefaults.standard
        let keys: [WindowConfigurationKey] = [
            .inputFieldCellVisible,
            .selectLanguageCellVisible,
        ]
        let legacyPriority: [EZWindowType] = [.fixed, .mini, .main]

        for key in keys {
            let unifiedKey = "EZConfiguration_\(key.stringValue)_Key"
            guard defaults.object(forKey: unifiedKey) == nil else { continue }

            for windowType in legacyPriority {
                let legacyKey =
                    "EZConfiguration_\(key.stringValue)_Window\(windowType.rawValue)_Key"
                if let value = defaults.object(forKey: legacyKey) {
                    defaults.set(value, forKey: unifiedKey)
                    break
                }
            }
        }
    }()
}
