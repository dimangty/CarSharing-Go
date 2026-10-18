# Highload Carsharing API Gateway Core 🚀

A high-performance, distributed API Gateway core for an enterprise-level carsharing service, focusing on authorization, session management, and transactional billing. The system is designed following **Clean Architecture** principles and optimized to handle hundreds of thousands of requests per second (RPS) with ultra-low latency.

## 🏗️ Architecture & Technology Stack

*   **Core Language:** Go 1.24+ (leveraging strong typing, high-performance concurrency via goroutines).
*   **Transport Layer:** gRPC (HTTP/2 multiplexing, binary serialization via Protocol Buffers).
*   **Database:** PostgreSQL 15+ (strict ACID compliance, connection pooling managed via `pgxpool`).
*   **Caching & Rate Limiting:** Redis 7 (In-memory storage utilizing atomic Lua scripting).

### 🧩 Security Pipeline (gRPC Unary Interceptors)

Every incoming request to the API Gateway must pass through a 3-tier security pipeline configured as a high-performance middleware chain (`ChainUnaryInterceptor`):
1.  **IP Rate Limiter:** Protects the system against DDoS attacks and brute-force bots. Uses an atomic Redis Lua script (`INCR` + `EXPIRE`) to track and limit RPS per IP address in-memory.
2.  **BruteForce Limiter:** Monitors and restricts failed `SignIn`/`SignUp` attempts for specific usernames, preventing account takeover attacks.
3.  **JWT Token Interceptor:** Handles stateless user authentication. Validates token cryptographic signatures (`HS256`), checks against an in-memory Redis session blacklist (revoked sessions), and securely injects the `user_id` into the request `context.Context` with zero allocations.

## 💳 Highload Billing Mechanics

*   **Idempotent Transactions (`Deposit`):** Client-side double-spending protection during wallet deposits. Managed atomically via Redis `SETNX` (with a 24-hour TTL) backed by PostgreSQL database-level strict unique constraints (`UniqueViolation 23505`).
*   **Asynchronous Webhooks:** Implements a fault-tolerant integration loop with a mock payment provider (`MyMoney`) using an asynchronous Callback model. Leverages a robust retry policy with custom delays on network timeouts.
*   **Device-Bound Sessions & Grace Period:** Token rotation (`AuthRefresh`) requires verification of the unique device fingerprint (`user_identify_string`). A built-in 5-minute Grace Period prevents session drops caused by instant cellular disconnections (e.g., when a user drives through a tunnel).
*   **Atomic Ride Deductions:** Car rental status management (`Rentals`) and financial settlement (`Pay`) are bound into a single internal ACID transaction. If a user's wallet has insufficient funds (`amount_penny < totalPrice`), PostgreSQL triggers an automatic rollback, preventing negative balances.

## 🛠️ Automation & CLI (Makefile)

The workspace is fully automated for quick local development and containerized deployment.

```bash
# 📦 Compile Protobuf schema into native Go files (gRPC)
make gen-proto

# 🐳 Spin up database infrastructure (Postgres + Redis) in Docker
make docker-up

# 🚀 Apply database schemas and migrations
make migrate-up

# 🧪 Run unit tests and core business logic tests
go test ./...

# 🛑 Teardown database infrastructure and containers
make docker-down
```

## 📂 Project Structure

```text
├── api/proto/             # Protocol Buffer schemas (auth, cars, rentals, history, mymoney)
├── cmd/
│   ├── gateway/           # Main gateway service entrypoint (main.go with Graceful Shutdown)
│   └── mymoney/           # Mock external payment provider microservice
├── internal/
│   ├── delivery/grpc/     # Delivery Layer: gRPC handlers and interceptors middleware
│   ├── domain/            # Domain Layer: pure models, explicit errors, and layer interfaces
│   ├── repository/        # Data Layer: SQL queries, transaction management, pgx repositories
│   └── service/           # Service Layer: core business logic engine
├── pkg/                   # Auto-generated code from protoc compiler
├── scripts/
│   ├── lua/               # High-performance Lua automation scripts for Redis
│   └── migrations/        # SQL migration scripts for relational database schemas
└── tokens/                # Core token utility manager for JWT handling
```
