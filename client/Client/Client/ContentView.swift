//
//  ContentView.swift
//  Client
//
//  Created by Дмитрий Быков on 02.11.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var flow: AuthFlow
    @State private var loginModel: LoginViewModel
    @State private var registrationModel: RegistrationViewModel

    init(repository: any AuthRepository, storage: any SessionStorage) {
        let flow = AuthFlow()
        _flow = State(initialValue: flow)
        _loginModel = State(initialValue: LoginViewModel(repository: repository, storage: storage, onSuccess: { flow.authenticated() }))
        _registrationModel = State(initialValue: RegistrationViewModel(repository: repository, storage: storage, onSuccess: { flow.authenticated() }))
    }

    var body: some View {
        NavigationStack {
            switch flow.screen {
            case .login:
                LoginScreen(model: loginModel, onRegistration: { flow.showRegistration() })
            case .registration:
                RegistrationScreen(model: registrationModel, onLogin: { flow.showLogin() })
            case .success:
                AuthSuccessScreen()
            }
        }
    }
}
