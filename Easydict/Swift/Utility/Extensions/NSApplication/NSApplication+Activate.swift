//
//  NSApplication+Activate.swift
//  Easydict
//
//  Created by TheQY71 on 2026/08/04.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit

extension NSApplication {
    /// Convenience method to activate the application
    ///
    /// - Note: Since new API `activate()` on macOS 14.0 not working as expected,
    ///   it doesn't bring app to front, so use old API for now.
    func activateApp() {
        logInfo("Activating application")
        activate(ignoringOtherApps: true)
    }
}
