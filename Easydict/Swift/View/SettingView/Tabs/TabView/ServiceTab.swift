//
//  ServiceTab.swift
//  Easydict
//
//  Created by phlpsong on 2024/1/6.
//  Copyright © 2024 izual. All rights reserved.
//

import Combine
import Foundation
import SFSafeSymbols
import SwiftUI

// MARK: - ServiceTab

struct ServiceTab: View {
    // MARK: Internal

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                List(
                    selection: Binding(
                        get: { viewModel.selectedItems },
                        set: { viewModel.selectItems($0) }
                    )
                ) {
                    Section {
                        WindowConfigurationItem()
                            .tag(ServiceTabSelection.windowConfiguration)
                    }

                    Section {
                        ServiceItems()
                    } header: {
                        Text("setting.service.list.services_header")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.never)
                .borderedCard()
                .onReceive(serviceHasUpdatedNotification) { _ in
                    viewModel.updateServices()
                }
            }
            .padding(12)
            .frame(minWidth: 270, maxWidth: 320, maxHeight: .infinity)

            ServiceDetailView()
                .layoutPriority(1)
        }
        .environmentObject(viewModel)
    }

    // MARK: Private

    @StateObject private var viewModel: ServiceTabViewModel = .init()

    private let serviceHasUpdatedNotification = NotificationCenter.default
        .publisher(for: .serviceHasUpdated)
}

// MARK: - ServiceTabSelection

enum ServiceTabSelection: Hashable {
    case windowConfiguration
    case service(String)
}

// MARK: - ServiceTabViewModel

/// Backs the service settings shared by every query window. `windowType`
/// selects the runtime context used to construct detail-view services; it no
/// longer scopes persistence.
@MainActor
class ServiceTabViewModel: ObservableObject {
    // MARK: Lifecycle

    init(windowType: EZWindowType = .fixed) {
        self.windowType = windowType
        self.serviceItems = Self.loadServiceItems(windowType)
    }

    // MARK: Internal

    @Published private(set) var serviceItems: [ServiceListItem]

    @Published private(set) var selectedService: QueryService?

    /// Canonical runtime context used by the unified settings UI.
    let windowType: EZWindowType

    @Published private(set) var selectedItems: Set<ServiceTabSelection> = [
        .windowConfiguration,
    ]

    func updateServices() {
        serviceItems = Self.loadServiceItems(windowType)

        let availableSelections = Set(
            serviceItems.map { ServiceTabSelection.service($0.id) }
        )
        let validSelections = selectedItems.filter {
            $0 == .windowConfiguration || availableSelections.contains($0)
        }
        setSelection(Set(validSelections), preferred: selectedItem)
    }

    func moveServices(fromOffsets: IndexSet, toOffset: Int) {
        var serviceItems = serviceItems
        serviceItems.move(fromOffsets: fromOffsets, toOffset: toOffset)

        let serviceTypes = serviceItems.map(\.id)
        LocalStorage.shared().setAllServiceTypes(serviceTypes, windowType: windowType)

        postUpdateServiceNotification()
        updateServices()
    }

    func selectItems(_ items: Set<ServiceTabSelection>) {
        let addedItems = items.subtracting(selectedItems)
        var selection = items

        if addedItems.contains(.windowConfiguration) {
            selection = [.windowConfiguration]
        } else {
            selection.remove(.windowConfiguration)
        }

        let preferredItem = orderedSelection(in: addedItems)
            ?? selectedItem
        setSelection(selection, preferred: preferredItem)
    }

    func setServiceEnabled(_ enabled: Bool, for item: ServiceListItem) {
        LocalStorage.shared().setServiceEnabled(
            enabled,
            serviceTypeId: item.id,
            windowType: windowType
        )
        if selectedService?.serviceTypeWithUniqueIdentifier() == item.id {
            selectedService?.enabled = enabled
        }

        postUpdateServiceNotification()
        reloadLLMSubscribersIfNeeded(for: [item])
        updateServices()
    }

    func validateAndEnable(_ item: ServiceListItem) async throws {
        guard item.isStream else {
            setServiceEnabled(true, for: item)
            return
        }

        guard let service = LocalStorage.shared().service(
            item.id,
            windowType: windowType
        ) else {
            return
        }
        let result = await service.validate()
        guard LocalStorage.shared()
            .allServiceTypes(windowType)
            .contains(item.id) else {
            return
        }
        if let error = result.error {
            throw error
        }
        service.enabled = true
        LocalStorage.shared().setServiceEnabled(
            true,
            serviceTypeId: item.id,
            windowType: windowType
        )
        postUpdateServiceNotification()
        GlobalContext.shared.reloadLLMServicesSubscribers()
        selectedService = selectedItem == .service(item.id) ? service : selectedService
        updateServices()
    }

    func postUpdateServiceNotification() {
        NotificationCenter.default.postServiceUpdateNotification()
    }

    // MARK: Private

    private var selectedItem: ServiceTabSelection? = .windowConfiguration

    private static func loadServiceItems(_ windowType: EZWindowType) -> [ServiceListItem] {
        serviceItems(from: LocalStorage.shared().allServiceTypes(windowType), windowType: windowType)
    }

    private static func serviceItems(
        from serviceTypeIds: [String],
        windowType: EZWindowType
    )
        -> [ServiceListItem] {
        serviceTypeIds.compactMap { typeId in
            guard let metadata = QueryServiceFactory.shared.metadata(withTypeId: typeId) else {
                return nil
            }
            let info = LocalStorage.shared().serviceInfo(
                withType: metadata.serviceType,
                serviceId: metadata.uuid,
                windowType: windowType
            )
            return ServiceListItem(
                id: typeId,
                type: metadata.serviceType,
                name: metadata.title,
                enabled: info?.enabled == true,
                requirement: metadata.apiKeyRequirement,
                isStream: metadata.isStream
            )
        }
    }

    private func updateSelectedService() {
        guard case let .service(serviceID) = selectedItem else {
            selectedService = nil
            return
        }
        guard serviceItems.contains(where: { $0.id == serviceID }) else {
            selectedService = nil
            return
        }
        selectedService = LocalStorage.shared().service(serviceID, windowType: windowType)
    }

    private func orderedSelection(
        in selections: Set<ServiceTabSelection>
    )
        -> ServiceTabSelection? {
        if selections.contains(.windowConfiguration) {
            return .windowConfiguration
        }
        return serviceItems.reversed().lazy
            .map { ServiceTabSelection.service($0.id) }
            .first { selections.contains($0) }
    }

    private func setSelection(
        _ selection: Set<ServiceTabSelection>,
        preferred: ServiceTabSelection? = nil
    ) {
        let selection = selection.isEmpty
            ? Set([ServiceTabSelection.windowConfiguration])
            : selection
        selectedItems = selection
        selectedItem = preferred.flatMap {
            selection.contains($0) ? $0 : nil
        } ?? orderedSelection(in: selection)
        updateSelectedService()
    }

    private func reloadLLMSubscribersIfNeeded(for items: [ServiceListItem]) {
        // Stream configuration observers follow the unified service list.
        guard items.contains(where: { $0.isStream }) else { return }
        GlobalContext.shared.reloadLLMServicesSubscribers()
    }
}

// MARK: - ServiceListItem

struct ServiceListItem: Identifiable {
    let id: String
    let type: ServiceType
    let name: String
    let enabled: Bool
    let requirement: ServiceAPIKeyRequirement
    let isStream: Bool
}

// MARK: - WindowConfigurationItem

private struct WindowConfigurationItem: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemSymbol: .macwindow)
                .font(.system(size: 13))
                .frame(width: 22, height: 22)
            Text("setting.service.window_configuration")
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .listRowSeparator(.hidden)
        .listRowInsets(.init())
    }
}

// MARK: - ServiceDetailView

private struct ServiceDetailView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if let service = viewModel.selectedService {
                if let view = service.configurationListItems() as? (any View) {
                    Form {
                        AnyView(view)
                    }
                    .formStyle(.grouped)
                } else {
                    VStack(spacing: 8) {
                        Image(systemSymbol: .checkmarkCircle)
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.quaternary)
                        Text("setting.service.detail.no_configuration \(service.name())")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                WindowConfigurationView()
            }
        }
    }

    // MARK: Private

    @EnvironmentObject private var viewModel: ServiceTabViewModel
}
