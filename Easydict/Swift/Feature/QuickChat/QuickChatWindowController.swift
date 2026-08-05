//
//  QuickChatWindowController.swift
//  Easydict
//
//  Created by TheQY71 on 2026/08/04.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SwiftUI

// MARK: - QuickChatPanel

/// A glance-and-dismiss panel that mirrors `EZBaseQueryWindow`'s presentation.
///
/// Being a non-activating panel lets it take keystrokes without pulling focus
/// away from whatever app the user was in, which is what makes the mini query
/// window feel lightweight. Escape dismisses it.
private final class QuickChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Invoked on Escape so the controller can also tear down its click monitors.
    var onCancel: (() -> ())?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

// MARK: - QuickChatWindowController

/// Manages the quick chat window.
///
/// The window is created once and reused so a streamed answer survives being
/// dismissed and reopened. It hides on Escape, on the quick chat shortcut, or on
/// a click outside it. Dismissal deliberately keys off clicks rather than
/// `windowDidResignKey`, which fires spuriously for a non-activating panel owned
/// by an LSUIElement app and made the window vanish as it appeared.
final class QuickChatWindowController: NSWindowController {
    // MARK: Lifecycle

    private init() {
        // `.fullSizeContentView` extends the content under the (transparent,
        // titleless) titlebar; without it a blank 28pt strip sits above the
        // input row.
        let panel = QuickChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "quick_chat.window_title")
        panel.isFloatingPanel = true
        // Easydict is an LSUIElement app: it deactivates the moment the menu bar
        // menu closes, and a panel hides itself on deactivation by default.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior.insert([.transient, .ignoresCycle])
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        // `EZWindowManager` raises query windows to this level when showing them
        // (`EZFloatingWindowLevel` == `kCGModalPanelWindowLevel`). Without it a window
        // ordered front from a background app can land behind the active app.
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        // Match `EZMiniQueryWindow`: no traffic lights, so the only ways out are
        // Escape, the shortcut, and clicking away.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.center()

        let viewModel = QuickChatViewModel()
        self.viewModel = viewModel
        panel.contentView = NSHostingView(rootView: QuickChatView(viewModel: viewModel))

        super.init(window: panel)
        panel.onCancel = { [weak self] in self?.hide() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    /// Posted after the window is shown so the input field can retake focus.
    /// The window is reused, so `onAppear` alone only fires for the first show.
    static let didShowNotification = Notification.Name("QuickChatWindowDidShow")

    static let shared = QuickChatWindowController()

    /// Shows the window, or hides it when already visible.
    ///
    /// The selection lookup is started before the window takes focus, matching the
    /// order `selectTextTranslate` relies on, but is never awaited: reading the
    /// selection needs Accessibility, and chat must still open when that is denied
    /// or slow. The text is filled in when it arrives, if the user has not started
    /// typing in the meantime.
    func toggle() {
        guard let window else { return }
        if window.isVisible {
            hide()
            return
        }

        let selectionTask = Task { await SystemUtility.shared.getSelectedText() }
        let questionBeforeShow = viewModel.question
        show(window)

        Task { @MainActor [weak self] in
            guard let self,
                  let selectedText = await selectionTask.value,
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  // Do not overwrite anything typed while the lookup was running.
                  viewModel.question == questionBeforeShow
            else {
                return
            }
            viewModel.reset()
            viewModel.question = selectedText
        }
    }

    /// Hides the window and tears down the click monitors.
    func hide() {
        stopOutsideClickMonitors()
        window?.orderOut(nil)
    }

    // MARK: Private

    private let viewModel: QuickChatViewModel

    /// Clicks in other applications.
    private var globalClickMonitor: Any?
    /// Clicks in Easydict's own windows, which the global monitor never sees.
    private var localClickMonitor: Any?

    /// Presents the window and starts watching for a click that should dismiss it.
    ///
    /// When triggered from the menu bar the menu is still tracking, and a window
    /// presented during tracking is swallowed. `EasydictApp` defers opening
    /// Settings for the same reason. The delay is harmless on the hotkey path.
    private func show(_ window: NSWindow) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: Self.didShowNotification, object: nil)
            startOutsideClickMonitors()
        }
    }

    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] _ in
            self?.hideIfClickedOutside()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown) { [weak self] event in
            self?.hideIfClickedOutside()
            return event
        }
    }

    private func stopOutsideClickMonitors() {
        [globalClickMonitor, localClickMonitor]
            .compactMap { $0 }
            .forEach(NSEvent.removeMonitor)
        globalClickMonitor = nil
        localClickMonitor = nil
    }

    /// Hides the window when the click landed on some other window.
    ///
    /// Asks AppKit which window sits under the cursor instead of testing the
    /// window frame. `EventMonitor` learned the hard way that frame math
    /// misjudges on-window clicks as "outside" on multi-display and scaled
    /// setups, dismissing the window mid-typing.
    private func hideIfClickedOutside() {
        guard let window, window.isVisible else {
            // Already dismissed some other way (Escape, close button); the monitors
            // have nothing left to watch.
            stopOutsideClickMonitors()
            return
        }

        let windowNumberAtPoint = NSWindow.windowNumber(
            at: NSEvent.mouseLocation,
            belowWindowWithWindowNumber: 0
        )
        if windowNumberAtPoint != window.windowNumber {
            hide()
        }
    }
}
