//
//  GlobalContext.swift
//  Easydict
//
//  Created by 戴藏龙 on 2024/1/25.
//  Copyright © 2024 izual. All rights reserved.
//

import Defaults
import Foundation

@objcMembers
class GlobalContext: NSObject {
    // MARK: Lifecycle

    private override init() {
        super.init()

        reloadLLMServicesSubscribers()
    }

    // MARK: Internal

    static let shared = GlobalContext()

    /// Rebuilds configuration observers for unified stream services.
    func reloadLLMServicesSubscribers() {
        logInfo("reloadLLMServicesSubscribers")

        for service in services {
            service.cancelSubscribers()
        }
        let storage = LocalStorage.shared()
        services = storage.allServiceTypes(.fixed).compactMap { typeId in
            guard QueryServiceFactory.shared.isStreamService(typeIdIfHave: typeId) else {
                return nil
            }
            return storage.service(typeId, windowType: .fixed) as? StreamService
        }
        for service in services {
            service.setupSubscribers()
        }
    }

    // MARK: Private

    // TODO: This code is not good, we should improve it later.

    /**
     Stream services observe shared configuration used by query windows and
     settings. `services` keeps one canonical instance per identifier alive for
     the app lifecycle.

     Configuration notifications currently create new service instances.
     Cancel old subscribers before replacing services because old instances may
     be retained elsewhere.
     */
    private var services: [StreamService] = []
}
