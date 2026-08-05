//
//  MenuBarClickRouter.swift
//  Easydict
//
//  Created by TheQY71 on 2026/08/04.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Combine
import Defaults

/// Routes menu bar icon clicks: left opens quick chat, right opens the menu.
///
/// SwiftUI's `MenuBarExtra` attaches its menu directly to the status item, so every
/// click pops the menu and no click reaches an action. This takes the menu off the
/// status item, installs an action instead, and puts the menu back only for the
/// duration of a right-click.
///
/// - Note: The status item is located through KVC on the private `NSStatusBarWindow`
///   class, since `MenuBarExtra` does not expose it. Every step is optional-guarded:
///   if a future macOS breaks the lookup, the takeover is skipped and the icon keeps
///   its stock behaviour of showing the menu on any click.
@objc(EZMenuBarClickRouter)
@objcMembers
final class MenuBarClickRouter: NSObject {
    // MARK: Internal

    static let shared = MenuBarClickRouter()

    /// Starts routing clicks, retrying while `MenuBarExtra` creates its status item.
    func install() {
        attemptInstall(remainingAttempts: 10)

        // Toggling the icon off and on recreates the status item, dropping the
        // takeover. `options: []` skips the emission on registration, which would
        // otherwise re-run a install that already succeeded.
        Defaults.publisher(.hideMenuBarIcon, options: [])
            .removeDuplicates()
            .sink { [weak self] change in
                guard !change.newValue else { return }
                self?.attemptInstall(remainingAttempts: 10)
            }
            .store(in: &cancellables)
    }

    // MARK: Private

    private static let statusItemKey = "statusItem"
    private static let statusItemSelector = NSSelectorFromString(statusItemKey)

    /// Retained so the menu can be restored for right-clicks.
    private var menu: NSMenu?
    private weak var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    /// Looks for the status item, retrying on a short delay until it exists.
    private func attemptInstall(remainingAttempts: Int) {
        if takeOverStatusItem() {
            return
        }
        guard remainingAttempts > 0 else {
            logError("Menu bar click routing unavailable; icon keeps default behaviour")
            logDiagnostics()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.attemptInstall(remainingAttempts: remainingAttempts - 1)
        }
    }

    /// - Returns: `true` once the status item was found and its action installed.
    private func takeOverStatusItem() -> Bool {
        guard let statusItem = findStatusItem(), let button = statusItem.button else {
            return false
        }

        // Already routing this item. The menu is detached once taken over, so this
        // must be checked before the menu guard below, which would otherwise read
        // as "not ready yet" forever.
        if button.target === self, menu != nil {
            self.statusItem = statusItem
            return true
        }

        guard let menu = statusItem.menu else {
            // The item exists but SwiftUI has not attached the menu yet; retry.
            return false
        }

        self.statusItem = statusItem
        self.menu = menu

        // The action only fires while no menu is attached.
        statusItem.menu = nil
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return true
    }

    /// Finds the status item `MenuBarExtra` created.
    ///
    /// Any window exposing a `statusItem` is accepted rather than matching on a
    /// class name, since the private window class has been renamed across releases.
    /// `responds(to:)` is checked first so a missing key returns nil instead of
    /// raising an Objective-C exception, which Swift could not catch.
    private func findStatusItem() -> NSStatusItem? {
        for window in NSApp.windows where window.responds(to: Self.statusItemSelector) {
            if let statusItem = window.value(forKey: Self.statusItemKey) as? NSStatusItem {
                return statusItem
            }
        }
        return nil
    }

    /// Records what the window list actually looked like, so a future macOS change
    /// can be diagnosed from the log instead of guesswork.
    private func logDiagnostics() {
        let descriptions = NSApp.windows.map { window in
            let respondsToKey = window.responds(to: Self.statusItemSelector)
            return "\(window.className)(statusItem: \(respondsToKey))"
        }
        logError("Windows searched: \(descriptions.joined(separator: ", "))")

        guard let statusItem = findStatusItem() else {
            logError("No window exposed an NSStatusItem")
            return
        }
        let button = statusItem.button
        let target = button?.target.map { String(describing: type(of: $0)) } ?? "nil"
        let action = button?.action.map { NSStringFromSelector($0) } ?? "nil"
        logError(
            "Status item: button=\(button != nil) menu=\(statusItem.menu != nil) "
                + "target=\(target) action=\(action)"
        )
    }

    /// Control-click is treated as a right-click, following macOS convention.
    @objc
    private func handleClick(_ button: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isSecondaryClick {
            showMenu(from: button)
        } else {
            QuickChatWindowController.shared.toggle()
        }
    }

    /// Reattaches the menu just long enough to display it.
    ///
    /// `performClick` blocks while the menu tracks, so clearing afterwards restores
    /// the action in time for the next click.
    private func showMenu(from button: NSStatusBarButton) {
        guard let statusItem, let menu else { return }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }
}
