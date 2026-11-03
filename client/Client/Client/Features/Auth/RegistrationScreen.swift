import SwiftUI

struct RegistrationScreen: View {
    @Bindable var model: RegistrationViewModel
    let onLogin: () -> Void
    @State private var requestTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("Логин", text: $model.login)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("registration.username")
                SecureField("Пароль", text: $model.password)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("registration.password")
                SecureField("Подтверждение пароля", text: $model.confirmation)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("registration.confirmation")
            }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("auth.error")
            }
            Section {
                Button {
                    requestTask = Task { await model.submit() }
                } label: {
                    HStack {
                        Text("Зарегистрироваться")
                        if model.isLoading { ProgressView().accessibilityLabel("Выполняется регистрация") }
                    }
                }
                .accessibilityIdentifier("registration.submit")
                Button("Вернуться ко входу", action: onLogin)
                    .accessibilityIdentifier("registration.login")
            }
        }
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .disabled(model.isLoading)
        .navigationTitle("Регистрация")
        .onDisappear { requestTask?.cancel() }
    }
}
