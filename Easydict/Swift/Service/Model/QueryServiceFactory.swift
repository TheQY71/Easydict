//
//  QueryServiceFactory.swift
//  Easydict
//
//  Created by tisfeng on 2025/12/16.
//  Copyright © 2025 izual. All rights reserved.
//

import Defaults
import Foundation

// MARK: - QueryServiceMetadata

struct QueryServiceMetadata {
    let serviceType: ServiceType
    let uuid: String
    let title: String
    let apiKeyRequirement: ServiceAPIKeyRequirement
    let isStream: Bool
    let allowsMultipleInstances: Bool
}

// MARK: - ServiceRegistration

private struct ServiceRegistration {
    // MARK: Lifecycle

    init(
        _ serviceType: ServiceType,
        _ serviceClass: QueryService.Type,
        _ titleKey: String,
        apiKeyRequirement: ServiceAPIKeyRequirement = .userProvided,
        allowsMultipleInstances: Bool = false,
        isSelectable: Bool = true
    ) {
        self.serviceType = serviceType
        self.serviceClass = serviceClass
        self.titleKey = titleKey
        self.apiKeyRequirement = apiKeyRequirement
        self.allowsMultipleInstances = allowsMultipleInstances
        self.isSelectable = isSelectable
    }

    // MARK: Internal

    let serviceType: ServiceType
    let serviceClass: QueryService.Type
    let titleKey: String
    let apiKeyRequirement: ServiceAPIKeyRequirement
    let allowsMultipleInstances: Bool

    /// Whether the service is offered as a query service in the settings list.
    /// Non-selectable services stay registered so other subsystems can still
    /// instantiate them, but never run as translation services.
    let isSelectable: Bool
}

// MARK: - QueryServiceFactory

/// A registry that maps `ServiceType` identifiers to their corresponding `QueryService` subclasses.
///
/// This class mirrors the legacy Objective-C `EZServiceTypes` API and stays accessible from both Objective-C and Swift.
@objcMembers
final class QueryServiceFactory: NSObject {
    // MARK: Internal

    /// Shared singleton instance.
    static let shared = QueryServiceFactory()

    var allServiceTypes: [ServiceType] {
        serviceRegistrations.map(\.serviceType)
    }

    var allServiceTypeIDs: [String] {
        allServiceTypes.map(\.rawValue)
    }

    func service(withTypeId typeIdIfHave: String) -> QueryService? {
        let components = serviceIdentifierComponents(from: typeIdIfHave)

        guard let serviceClass = serviceClass(withTypeId: typeIdIfHave) else {
            return nil
        }

        let service = serviceClass.init()
        service.uuid = components.uuid
        return service
    }

    /// Type identifiers offered as query services in the settings list.
    func isSelectable(typeIdIfHave: String) -> Bool {
        serviceRegistration(withTypeId: typeIdIfHave)?.isSelectable ?? false
    }

    func services(fromTypes types: [String]) -> [QueryService] {
        types.compactMap { service(withTypeId: $0) }
    }

    func isStreamService(typeIdIfHave: String) -> Bool {
        guard let serviceClass = serviceClass(withTypeId: typeIdIfHave) else {
            return false
        }
        return serviceClass is StreamService.Type
    }

    func metadata(withTypeId typeIdIfHave: String) -> QueryServiceMetadata? {
        let components = serviceIdentifierComponents(from: typeIdIfHave)
        guard let registration = serviceRegistration(withTypeId: typeIdIfHave) else { return nil }

        return QueryServiceMetadata(
            serviceType: registration.serviceType,
            uuid: components.uuid,
            title: title(
                for: registration.serviceType,
                uuid: components.uuid,
                fallbackKey: registration.titleKey
            ),
            apiKeyRequirement: registration.apiKeyRequirement,
            isStream: registration.serviceClass is StreamService.Type,
            allowsMultipleInstances: registration.allowsMultipleInstances
        )
    }

    // MARK: Private

    private let serviceRegistrations: [ServiceRegistration] = [
        .init(.youdao, YoudaoService.self, "youdao_dict", apiKeyRequirement: .none),
        .init(.deepSeek, DeepSeekService.self, "deepseek_translate"),
        .init(.polishing, PolishingService.self, "polishing_service", apiKeyRequirement: .builtIn),

        // Not offered as translation services; registered because other subsystems
        // resolve them through this factory: Apple/Google/Baidu back language
        // detection, and Apple/Google/Baidu/Bing/Youdao are the text-to-speech
        // options. `OpenAIService` and `BuiltInAIService` additionally sit in the
        // class hierarchy above DeepSeek and Polishing.
        .init(.apple, AppleService.self, "apple_translate", apiKeyRequirement: .none, isSelectable: false),
        .init(.google, GoogleService.self, "google_translate", apiKeyRequirement: .none, isSelectable: false),
        .init(.baidu, BaiduService.self, "baidu_translate", isSelectable: false),
        .init(.bing, BingService.self, "bing_translate", apiKeyRequirement: .none, isSelectable: false),
    ]

    private func serviceClass(withTypeId typeIdIfHave: String) -> QueryService.Type? {
        serviceRegistration(withTypeId: typeIdIfHave)?.serviceClass
    }

    private func serviceRegistration(withTypeId typeIdIfHave: String) -> ServiceRegistration? {
        let components = serviceIdentifierComponents(from: typeIdIfHave)
        return serviceRegistrations.first { $0.serviceType.rawValue == components.rawType }
    }

    private func serviceIdentifierComponents(from typeIdIfHave: String)
        -> (rawType: String, uuid: String) {
        let components = typeIdIfHave.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let rawType = String(components.first ?? Substring(typeIdIfHave))
        let uuid = components.count > 1 ? String(components[1]) : ""
        return (rawType, uuid)
    }

    private func title(for serviceType: ServiceType, uuid: String, fallbackKey: String) -> String {
        if serviceType == .customOpenAI {
            let nameKey = serivceConfigurationKey(
                .name,
                serviceType: serviceType,
                id: uuid,
                defaultValue: ""
            )
            let customName = Defaults[nameKey]
            if !customName.isEmpty {
                return customName
            }
        }
        return NSLocalizedString(fallbackKey, comment: "")
    }
}
