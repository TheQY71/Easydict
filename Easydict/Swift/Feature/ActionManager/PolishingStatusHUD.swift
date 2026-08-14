//
//  PolishingStatusHUD.swift
//  Easydict
//
//  Created by TheQY71 on 2026/08/13.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SFSafeSymbols
import SwiftUI

// MARK: - PolishingStatusHUD

/// Displays polishing progress without activating Easydict or disturbing the
/// selection in the target application. Terminal messages dismiss automatically,
/// while progress remains visible until the action produces an outcome.
@MainActor
final class PolishingStatusHUD {
    // MARK: Lifecycle

    private init() {
        self.panel = PolishingStatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PolishingStatusView(model: model))
    }

    // MARK: Internal

    static let shared = PolishingStatusHUD()

    func showProcessing() {
        show(message: "action.polish_and_replace.processing", style: .processing)
    }

    func showSuccess() {
        show(message: "action.polish_and_replace.success", style: .success)
    }

    func showError(_ message: LocalizedStringResource) {
        show(message: message, style: .error)
    }

    // MARK: Private

    private let model = PolishingStatusModel()
    private let panel: PolishingStatusPanel
    private var dismissTask: Task<(), Never>?

    private func show(message: LocalizedStringResource, style: PolishingStatusStyle) {
        dismissTask?.cancel()
        model.message = String(localized: message)
        model.style = style
        positionPanel()
        panel.orderFrontRegardless()

        guard style != .processing else { return }
        dismissTask = Task { @MainActor [weak self] in
            await Task.sleep(seconds: 4)
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let panelSize = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.maxX - panelSize.width - 20,
                y: visibleFrame.maxY - panelSize.height - 20
            )
        )
    }
}

// MARK: - PolishingStatusPanel

/// A non-activating panel that can never become the key or main window.
private final class PolishingStatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - PolishingStatusModel

/// Observable content rendered in the polishing status panel.
@MainActor
private final class PolishingStatusModel: ObservableObject {
    @Published var message = ""
    @Published var style = PolishingStatusStyle.processing
}

// MARK: - PolishingStatusStyle

/// Visual states supported by the polishing status panel.
private enum PolishingStatusStyle {
    case processing
    case success
    case error
}

// MARK: - PolishingStatusView

/// Compact SwiftUI content for polishing progress and terminal feedback.
@MainActor
private struct PolishingStatusView: View {
    // MARK: Internal

    @ObservedObject var model: PolishingStatusModel

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 20, height: 20)
            Text(model.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(width: 340, height: 60)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .padding(10)
    }

    // MARK: Private

    @ViewBuilder private var statusIcon: some View {
        switch model.style {
        case .processing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemSymbol: .checkmarkCircleFill)
                .foregroundStyle(.green)
        case .error:
            Image(systemSymbol: .exclamationmarkTriangleFill)
                .foregroundStyle(.orange)
        }
    }
}
