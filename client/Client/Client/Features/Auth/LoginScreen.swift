import SwiftUI

struct LoginScreen: View {
    @Bindable var model: LoginViewModel
    let onRegistration: () -> Void
    @State private var requestTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("Логин", text: $model.login)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("login.username")
                SecureField("Пароль", text: $model.password)
                    .textContentType(.password)
                    .accessibilityIdentifier("login.password")
            }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("auth.error")
            }
            Section {
                Button {
                    requestTask = Task { await model.submit() }
                } label: {
                    HStack {
                        Text("Войти")
                        if model.isLoading { ProgressView().accessibilityLabel("Выполняется вход") }
                    }
                }
                .accessibilityIdentifier("login.submit")
                Button("Регистрация", action: onRegistration)
                    .accessibilityIdentifier("login.registration")
            }
        }
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .disabled(model.isLoading)
        .navigationTitle("Вход")
        .onDisappear { requestTask?.cancel() }
    }
}
