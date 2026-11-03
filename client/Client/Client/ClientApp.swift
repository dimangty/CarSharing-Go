//
//  ClientApp.swift
//  Client
//
//  Created by Дмитрий Быков on 02.11.2026.
//

import SwiftUI

@main
struct ClientApp: App {
    private let configuration = Result { try GRPCConfiguration.application() }

    var body: some Scene {
        WindowGroup {
            switch configuration {
            case .success(let configuration):
                ContentView(
                    repository: GRPCAuthRepository(client: GRPCClient(configuration: configuration)),
                    storage: KeychainSessionStorage()
                )
            case .failure(let error):
                ContentUnavailableView("Ошибка конфигурации", systemImage: "network.slash", description: Text(AuthError.message(for: error)))
            }
        }
    }
}
