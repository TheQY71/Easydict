//
//  StreamService+Configuation.swift
//  Easydict
//
//  Created by tisfeng on 2024/6/28.
//  Copyright © 2024 izual. All rights reserved.
//

import Defaults
import Foundation
import Security

extension StreamService {
    /// Environment variables accepted as fallback API key sources.
    /// The Easydict-scoped name wins over the provider's conventional name.
    var apiKeyEnvironmentVariableNames: [String] {
        let identifier = apiKeyEnvironmentServiceType.rawValue.unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map { String($0).uppercased() }
            .joined()
        guard !identifier.isEmpty else { return [] }
        return [
            "EASYDICT_\(identifier)_API_KEY",
            "\(identifier)_API_KEY",
        ]
    }

    /// Name of the environment variable currently providing the effective key.
    var activeAPIKeyEnvironmentVariable: String? {
        guard Defaults[apiKeyKey].trim().isEmpty else { return nil }
        return apiKeyEnvironmentVariableNames.first { variable in
            ProcessInfo.processInfo.environment[variable]?.trim().isEmpty == false
        }
    }

    /// Returns an environment key without persisting it in user defaults.
    var apiKeyFromEnvironment: String? {
        guard let variable = activeAPIKeyEnvironmentVariable else { return nil }
        return ProcessInfo.processInfo.environment[variable]?.trim()
    }

    /// Keychain services accepted as fallback API key sources.
    var apiKeyKeychainServiceNames: [String] {
        apiKeyEnvironmentVariableNames.map { "shell-api:\($0)" }
    }

    /// Name of the Keychain item currently providing the effective key.
    var activeAPIKeyKeychainService: String? {
        guard Defaults[apiKeyKey].trim().isEmpty else { return nil }
        return keychainAPIKeySource?.serviceName
    }

    /// Returns a Keychain key without copying it into Easydict's settings.
    var apiKeyFromKeychain: String? {
        guard Defaults[apiKeyKey].trim().isEmpty else { return nil }
        return keychainAPIKeySource?.key
    }

    /// Finds a generic-password item created for a shell API variable.
    private var keychainAPIKeySource: (serviceName: String, key: String)? {
        for serviceName in apiKeyKeychainServiceNames {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: NSUserName(),
                kSecAttrService: serviceName,
                kSecMatchLimit: kSecMatchLimitOne,
                kSecReturnData: true,
            ]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data,
                  let key = String(data: data, encoding: .utf8)?.trim(),
                  !key.isEmpty
            else {
                continue
            }
            return (serviceName, key)
        }
        return nil
    }

    /// Whether a defaults key represents the API key used by this service.
    /// Polishing observes DeepSeek's key, so both storage identities are checked.
    func isAPIKeyConfigurationKey(_ key: Defaults.Key<String>) -> Bool {
        let environmentServiceKey = serivceConfigurationKey(
            .apiKey,
            serviceType: apiKeyEnvironmentServiceType,
            defaultValue: ""
        )
        return key == apiKeyKey || key == environmentServiceKey
    }

    func setupSubscribers() {
        logInfo("setup subscribers: \(self), windowType: \(windowType.rawValue)")

        Defaults.publisher(nameKey, options: [])
            .removeDuplicates()
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.notifyServiceConfigurationChanged()
            }
            .store(in: &cancellables)

        Defaults.publisher(modelKey, options: [])
            .removeDuplicates()
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                self?.modelDidChanged($0.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(supportedModelsKey, options: [])
            .removeDuplicates()
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                self?.supportedModelsTextDidChanged($0.newValue)
            }
            .store(in: &cancellables)
    }

    func cancelSubscribers() {
        logInfo("cancel subscribers: \(self), windowType: \(windowType.rawValue)")
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    func modelDidChanged(_ newModel: String) {
        model = newModel

        // Handle some special cases
        if !validModels.contains(newModel) {
            if newModel.isEmpty {
                supportedModels = ""
            } else {
                if supportedModels.isEmpty {
                    supportedModels = newModel
                } else {
                    supportedModels = "\(newModel), " + supportedModels
                }
            }
        }
        notifyServiceConfigurationChanged(autoQuery: true)
    }

    func supportedModelsTextDidChanged(_ newSupportedModels: String) {
        supportedModels = newSupportedModels

        if validModels.isEmpty {
            model = ""
        } else if !validModels.contains(model) {
            model = validModels[0]
        }
    }

    func notifyServiceConfigurationChanged(autoQuery: Bool = false) {
        logInfo("service config changed: \(serviceType().rawValue), windowType: \(windowType.rawValue)")
        if !uuid.isEmpty {
            logInfo("service name: \(name()), id: \(serviceTypeWithUniqueIdentifier())")
        }

        NotificationCenter.default.postServiceUpdateNotification(
            serviceType: serviceTypeWithUniqueIdentifier(),
            autoQuery: autoQuery
        )
    }
}

extension QueryService {
    func stringDefaultsKey(_ key: ServiceConfigurationKey) -> Defaults.Key<String> {
        stringDefaultsKey(key, defaultValue: "")
    }

    func stringDefaultsKey(_ key: ServiceConfigurationKey, defaultValue: String) -> Defaults.Key<String> {
        serivceConfigurationKey(key, serviceType: serviceType(), id: uuid, defaultValue: defaultValue)
    }

    func boolDefaultsKey(_ key: ServiceConfigurationKey, defaultValue: Bool) -> Defaults.Key<Bool> {
        serivceConfigurationKey(key, serviceType: serviceType(), id: uuid, defaultValue: defaultValue)
    }

    func serviceDefaultsKey<T>(_ key: ServiceConfigurationKey, defaultValue: T) -> Defaults.Key<T> {
        serivceConfigurationKey(key, serviceType: serviceType(), id: uuid, defaultValue: defaultValue)
    }
}
