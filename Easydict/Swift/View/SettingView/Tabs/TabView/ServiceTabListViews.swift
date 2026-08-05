//
//  ServiceTabListViews.swift
//  Easydict
//
//  Created by MoonMao on 2026/5/27.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SFSafeSymbols
import SwiftUI

// MARK: - ServiceItems

struct ServiceItems: View {
    // MARK: Internal

    var body: some View {
        ForEach(viewModel.serviceItems) { item in
            ServiceItemView(item: item)
                .tag(ServiceTabSelection.service(item.id))
        }
        .onMove { source, destination in
            viewModel.moveServices(fromOffsets: source, toOffset: destination)
        }
    }

    // MARK: Private

    @EnvironmentObject private var viewModel: ServiceTabViewModel
}

// MARK: - ServiceItemView

private struct ServiceItemView: View {
    // MARK: Internal

    let item: ServiceListItem

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ServiceIcon(type: item.type, iconSize: 18, containerSize: 22)
                Text(verbatim: item.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            ServiceRequirementBadge(requirement: item.requirement)

            ZStack {
                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    // Magnet can trigger a SwiftUI List(selection:) edge case where the
                    // first click on an unselected row selects the row before Toggle sees it.
                    // The Button handles clicks while Toggle only renders the switch.
                    Button {
                        toggleEnabled()
                    } label: {
                        Toggle(item.name, isOn: .constant(item.enabled))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .allowsHitTesting(false)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(width: 40, alignment: .center)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(.init())
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .alert(
            "setting.service.failed_to_enable_service \(item.name)",
            isPresented: $showErrorAlert
        ) {
            Button("ok") {
                showErrorAlert = false
            }
        } message: {
            Text(error?.localizedDescription ?? "unknown_error")
        }
        .alert(
            "service.claude_code.enable_risk_alert.title",
            isPresented: $showClaudeCodeRiskAlert
        ) {
            Button("cancel", role: .cancel) {
                showClaudeCodeRiskAlert = false
            }
            Button("ok") {
                showClaudeCodeRiskAlert = false
                enableService()
            }
        } message: {
            Text("service.claude_code.enable_risk_alert.message")
        }
        .alert(
            "service.codex_cli.enable_risk_alert.title",
            isPresented: $showCodexCLIRiskAlert
        ) {
            Button("cancel", role: .cancel) {
                showCodexCLIRiskAlert = false
            }
            Button("ok") {
                showCodexCLIRiskAlert = false
                enableService()
            }
        } message: {
            Text("service.codex_cli.enable_risk_alert.message")
        }
    }

    // MARK: Private

    @State private var isValidating = false
    @State private var showErrorAlert = false
    @State private var showClaudeCodeRiskAlert = false
    @State private var showCodexCLIRiskAlert = false
    @State private var error: (any Error)?

    @EnvironmentObject private var viewModel: ServiceTabViewModel

    /// Toggles the service on or off. Enabling Claude Code or Codex CLI first
    /// prompts a risk confirmation; other services enable directly.
    private func toggleEnabled() {
        guard !item.enabled else {
            viewModel.setServiceEnabled(false, for: item)
            return
        }

        if item.type == .claudeCode {
            showClaudeCodeRiskAlert = true
        } else if item.type == .codexCLI {
            showCodexCLIRiskAlert = true
        } else {
            enableService()
        }
    }

    private func enableService() {
        guard item.isStream else {
            viewModel.setServiceEnabled(true, for: item)
            return
        }

        isValidating = true
        Task { @MainActor in
            defer { isValidating = false }
            do {
                try await viewModel.validateAndEnable(item)
            } catch {
                logError("\(item.type.rawValue) validate error: \(error)")
                self.error = error
                showErrorAlert = true
            }
        }
    }
}

// MARK: - ServiceIcon

private struct ServiceIcon: View {
    let type: ServiceType
    let iconSize: CGFloat
    let containerSize: CGFloat

    var body: some View {
        Image(type.rawValue)
            .resizable()
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .frame(width: containerSize, height: containerSize)
    }
}

// MARK: - ServiceRequirementBadge

private struct ServiceRequirementBadge: View {
    // MARK: Internal

    let requirement: ServiceAPIKeyRequirement

    var body: some View {
        Text(titleKey)
            .font(.caption2.weight(.medium))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(backgroundColor)
            }
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 0.5)
            }
    }

    // MARK: Private

    private var titleKey: LocalizedStringKey {
        switch requirement {
        case .none:
            "service.badge.no_key"
        case .builtIn:
            "service.badge.built_in"
        case .userProvided:
            "service.badge.key_required"
        case .agentCLI:
            "service.badge.cli"
        }
    }

    private var foregroundColor: Color {
        switch requirement {
        case .none:
            .secondary
        case .builtIn:
            .green
        case .userProvided:
            .orange
        case .agentCLI:
            .blue
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }

    private var borderColor: Color {
        foregroundColor.opacity(0.28)
    }
}
