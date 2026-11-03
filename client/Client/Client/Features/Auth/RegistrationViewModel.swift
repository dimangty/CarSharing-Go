import Foundation
import Observation

@MainActor @Observable
final class RegistrationViewModel {
    var login = ""
    var password = ""
    var confirmation = ""
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let repository: any AuthRepository
    private let storage: any SessionStorage
    private let onSuccess: () -> Void

    init(repository: any AuthRepository, storage: any SessionStorage, onSuccess: @escaping () -> Void) {
        self.repository = repository
        self.storage = storage
        self.onSuccess = onSuccess
    }

    func submit() async {
        guard !isLoading else { return }
        errorMessage = nil
        let normalizedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLogin.isEmpty else { errorMessage = "Введите логин."; return }
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Введите пароль."; return
        }
        guard !confirmation.isEmpty, password == confirmation else {
            errorMessage = "Пароли должны совпадать."; return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try Task.checkCancellation()
            let session = try await repository.signUp(login: normalizedLogin, password: password, confirmation: confirmation)
            try Task.checkCancellation()
            try storage.save(session)
            password = ""
            confirmation = ""
            onSuccess()
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = AuthError.message(for: error) }
        }
    }
}
