import XCTest
import GRPCCore
#if canImport(Client)
@testable import Client
#else
@testable import ClientAuth
#endif

@MainActor
final class AuthViewModelTests: XCTestCase {
    func testLoginValidationNeverCallsNetwork() async {
        for (login, password) in [("", "123456"), (" \n", "123456"), ("test", ""), ("test", " \t")] {
            let repository = ControlledRepository()
            let model = LoginViewModel(repository: repository, storage: MemoryStorage(), onSuccess: {})
            model.login = login
            model.password = password
            await model.submit()
            XCTAssertNotNil(model.errorMessage)
            XCTAssertFalse(model.isLoading)
            XCTAssertEqual(repository.requests.count, 0)
        }
    }

    func testRegistrationValidationNeverCallsNetwork() async {
        for (login, password, confirmation) in [
            ("", "123456", "123456"), (" \n", "123456", "123456"),
            ("test", "", ""), ("test", " \t", " \t"),
            ("test", "123456", ""), ("test", "123456", "different"),
        ] {
            let repository = ControlledRepository()
            let model = RegistrationViewModel(repository: repository, storage: MemoryStorage(), onSuccess: {})
            model.login = login
            model.password = password
            model.confirmation = confirmation
            await model.submit()
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(repository.requests.count, 0)
        }
    }

    func testLoginLoadingRejectsDuplicatesAndStoresResponseBeforeSuccess() async {
        let repository = ControlledRepository()
        let storage = MemoryStorage()
        var succeeded = false
        let model = LoginViewModel(repository: repository, storage: storage, onSuccess: { succeeded = true })
        model.login = " test "
        model.password = "123456"
        let task = Task { await model.submit() }
        await repository.waitForRequest()
        XCTAssertTrue(model.isLoading)
        await model.submit()
        XCTAssertEqual(repository.requests, [.signIn("test", "123456")])
        XCTAssertFalse(succeeded)
        repository.complete(.success(session))
        await task.value
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(storage.saved, session)
        XCTAssertEqual(model.password, "")
    }

    func testRegistrationLoadingRejectsDuplicatesAndHandlesSuccess() async {
        let repository = ControlledRepository()
        let storage = MemoryStorage()
        let flow = AuthFlow()
        flow.showRegistration()
        let model = RegistrationViewModel(repository: repository, storage: storage, onSuccess: { flow.authenticated() })
        model.login = "new_user"
        model.password = "123456"
        model.confirmation = "123456"
        let task = Task { await model.submit() }
        await repository.waitForRequest()
        XCTAssertTrue(model.isLoading)
        await model.submit()
        XCTAssertEqual(repository.requests, [.signUp("new_user", "123456", "123456")])
        repository.complete(.success(session))
        await task.value
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(flow.screen, .success)
        XCTAssertEqual(storage.saved, session)
        XCTAssertEqual(model.password, "")
        XCTAssertEqual(model.confirmation, "")
    }

    func testErrorAllowsEditingAndRetry() async {
        let repository = ControlledRepository()
        let storage = MemoryStorage()
        let model = LoginViewModel(repository: repository, storage: storage, onSuccess: {})
        model.login = "test"
        model.password = "123456"
        let first = Task { await model.submit() }
        await repository.waitForRequest()
        repository.complete(.failure(RPCError(code: .unavailable, message: "offline")))
        await first.value
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(storage.saved)
        model.login = "another_user"
        let retry = Task { await model.submit() }
        await repository.waitForRequest()
        XCTAssertNil(model.errorMessage)
        repository.complete(.success(session))
        await retry.value
        XCTAssertEqual(repository.requests.count, 2)
        XCTAssertEqual(storage.saved, session)
    }

    func testStorageFailureDoesNotAuthenticate() async {
        let repository = ControlledRepository()
        let storage = MemoryStorage()
        storage.shouldFail = true
        var succeeded = false
        let model = RegistrationViewModel(repository: repository, storage: storage, onSuccess: { succeeded = true })
        model.login = "test"
        model.password = "123456"
        model.confirmation = "123456"
        let task = Task { await model.submit() }
        await repository.waitForRequest()
        repository.complete(.success(session))
        await task.value
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(succeeded)
    }

    func testCancellationRestoresInputWithoutSuccess() async {
        let repository = ControlledRepository()
        var succeeded = false
        let model = LoginViewModel(repository: repository, storage: MemoryStorage(), onSuccess: { succeeded = true })
        model.login = "test"
        model.password = "123456"
        let task = Task { await model.submit() }
        await repository.waitForRequest()
        task.cancel()
        repository.complete(.success(session))
        await task.value
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(succeeded)
        XCTAssertNil(model.errorMessage)
    }

    func testNavigationBetweenFormsAndSuccess() {
        let flow = AuthFlow()
        XCTAssertEqual(flow.screen, .login)
        flow.showRegistration()
        XCTAssertEqual(flow.screen, .registration)
        flow.showLogin()
        XCTAssertEqual(flow.screen, .login)
        flow.authenticated()
        XCTAssertEqual(flow.screen, .success)
    }
}

private let session = AuthSession(accessToken: "mock_access_token", refreshToken: "mock_refresh_token")

@MainActor
final class MemoryStorage: SessionStorage {
    var saved: AuthSession?
    var shouldFail = false
    func save(_ session: AuthSession) throws {
        if shouldFail { throw AuthError.storage }
        saved = session
    }
}

@MainActor
final class ControlledRepository: AuthRepository {
    enum Request: Equatable {
        case signIn(String, String)
        case signUp(String, String, String)
    }
    var requests: [Request] = []
    private var continuation: CheckedContinuation<AuthSession, any Error>?
    private var started: CheckedContinuation<Void, Never>?

    func signIn(login: String, password: String) async throws -> AuthSession {
        try await suspend(.signIn(login, password))
    }
    func signUp(login: String, password: String, confirmation: String) async throws -> AuthSession {
        try await suspend(.signUp(login, password, confirmation))
    }
    private func suspend(_ request: Request) async throws -> AuthSession {
        requests.append(request)
        return try await withCheckedThrowingContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }
    func waitForRequest() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func complete(_ result: Result<AuthSession, any Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}
