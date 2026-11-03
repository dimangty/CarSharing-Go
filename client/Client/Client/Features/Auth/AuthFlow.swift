import Observation

@MainActor @Observable
final class AuthFlow {
    enum Screen { case login, registration, success }
    private(set) var screen: Screen = .login

    func showLogin() { screen = .login }
    func showRegistration() { screen = .registration }
    func authenticated() { screen = .success }
}
