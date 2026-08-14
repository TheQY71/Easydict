//
//  SystemUtility+Shortcut(.swift
//  Easydict
//
//  Created by tisfeng on 2025/9/2.
//  Copyright © 2025 izual. All rights reserved.
//

import AppKit
import Foundation
import KeySender
import SelectedTextKit

/// Minimum interval for pasteboard operations
let minPasteboardInterval: TimeInterval = 0.05

// MARK: - SystemUtility + Shortcut

extension SystemUtility {
    /// Select all text by shortcut key Command + A
    func selectAllByShortcut() async {
        logInfo("Select all text by hotkey Command + A")

        KeySender.selectAll()
        await Task.sleep(seconds: minPasteboardInterval)
    }

    /// Insert text by shortcut key, cmd+c and ctrl+v
    func insertTextByShortcut(
        _ text: String,
        restorePasteboard: Bool = true,
        restoreInterval: TimeInterval = minPasteboardInterval
    ) async
        -> Bool {
        let didPaste = await performTemporaryPaste(
            text: text,
            restorePasteboard: restorePasteboard,
            restoreInterval: restoreInterval
        ) {
            KeySender.paste()
            return true
        }
        return didPaste
    }

    /// Runs a paste action without logging the copied text and restores even an
    /// originally empty pasteboard.
    @MainActor
    func performTemporaryPaste(
        text: String,
        restorePasteboard: Bool,
        restoreInterval: TimeInterval,
        action: () async -> Bool
    ) async
        -> Bool {
        guard !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        let savedItems = restorePasteboard ? pasteboard.backupItems() : nil
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restorePasteboardItems(savedItems)
            return false
        }

        let result = await action()
        await Task.sleep(seconds: restoreInterval)
        restorePasteboardItems(savedItems)
        return result
    }

    @MainActor
    private func restorePasteboardItems(_ items: [NSPasteboardItem]?) {
        guard let items else { return }
        if items.isEmpty {
            NSPasteboard.general.clearContents()
        } else {
            NSPasteboard.general.restoreItems(items)
        }
    }
}
