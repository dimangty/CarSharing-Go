import Foundation

struct GRPCConfiguration: Sendable {
    let host: String
    let port: Int
    let useTLS: Bool

    init(values: [String: String], isDebug: Bool) throws {
        let host = (values["GRPC_HOST"] ?? (isDebug ? "localhost" : ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty,
              let port = Int(values["GRPC_PORT"] ?? "50051"), (1...65535).contains(port) else {
            throw AuthError.configuration
        }
        let tls: Bool
        switch values["GRPC_TLS"]?.lowercased() {
        case nil: tls = !isDebug
        case "true": tls = true
        case "false": tls = false
        default: throw AuthError.configuration
        }
        guard isDebug || tls else { throw AuthError.configuration }
        self.host = host
        self.port = port
        self.useTLS = tls
    }

    static func application(bundle: Bundle = .main) throws -> Self {
        var values: [String: String] = [:]
        for key in ["GRPC_HOST", "GRPC_PORT", "GRPC_TLS"] {
            if let value = bundle.object(forInfoDictionaryKey: key) as? String, !value.isEmpty {
                values[key] = value
            }
            if let value = ProcessInfo.processInfo.environment[key] { values[key] = value }
        }
        #if DEBUG
        return try Self(values: values, isDebug: true)
        #else
        return try Self(values: values, isDebug: false)
        #endif
    }
}
