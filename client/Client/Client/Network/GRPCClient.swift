import GRPCCore
import GRPCNIOTransportHTTP2TransportServices

struct GRPCClient: Sendable {
    let configuration: GRPCConfiguration

    // A scoped client owns the HTTP/2 connection for one operation. The library
    // closes connections on success, failure and structured-task cancellation.
    func withAuthClient<Result: Sendable>(
        _ operation: @Sendable (Auth_AuthService.Client<HTTP2ClientTransport.TransportServices>) async throws -> Result
    ) async throws -> Result {
        do {
            let transport = try HTTP2ClientTransport.TransportServices(
                target: .dns(host: configuration.host, port: configuration.port),
                transportSecurity: configuration.useTLS ? .tls : .plaintext
            )
            #if DEBUG
            let interceptors: [any ClientInterceptor] = [GRPCLoggingInterceptor()]
            #else
            let interceptors: [any ClientInterceptor] = []
            #endif
            return try await withGRPCClient(transport: transport, interceptors: interceptors) { client in
                try await operation(Auth_AuthService.Client(wrapping: client))
            }
        } catch {
            #if DEBUG
            // Connection failures may happen before a stream reaches the interceptor.
            print("[gRPC] event=client_error endpoint=\(configuration.host):\(configuration.port) status=\(GRPCLoggingInterceptor.status(for: error))")
            #endif
            throw error
        }
    }

    static var callOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(10)
        return options
    }
}
