import Foundation
import GRPCCore

enum AuthError: Error, LocalizedError {
    case configuration
    case invalidResponse
    case storage

    var errorDescription: String? {
        switch self {
        case .configuration: "Проверьте настройки адреса, порта и TLS сервера."
        case .invalidResponse: "Сервер не подтвердил авторизацию. Попробуйте ещё раз."
        case .storage: "Не удалось сохранить токены в Keychain. Попробуйте ещё раз."
        }
    }

    static func message(for error: any Error) -> String {
        if let error = error as? AuthError { return error.errorDescription! }
        guard let rpc = error as? RPCError else {
            return "Не удалось выполнить запрос. Проверьте соединение и попробуйте ещё раз."
        }
        switch rpc.code {
        case .invalidArgument: return "Проверьте логин, пароль и подтверждение пароля."
        case .unauthenticated, .permissionDenied: return "Не удалось войти. Проверьте введённые данные."
        case .unavailable: return "Сервер недоступен. Проверьте адрес сервера и соединение."
        case .deadlineExceeded: return "Сервер не ответил вовремя. Попробуйте ещё раз."
        case .resourceExhausted: return "Слишком много запросов. Попробуйте позже."
        case .unimplemented: return "Авторизация недоступна. Для локального теста включите mock-режим сервера."
        case .cancelled: return "Запрос отменён. Можно попробовать ещё раз."
        default: return "Ошибка сервера. Попробуйте ещё раз."
        }
    }
}
