# --- Config vars ---
DB_URL=postgres://user:password@localhost:5433/carsharing_db?sslmode=disable
MIGRATIONS_DIR=scripts/migrations
COMPOSE_FILE=deployments/docker-compose.yaml
PROTO_DIR=api/proto
PKG_DIR=pkg

# find all .protos
PROTO_FILES=$(shell find ./$(PROTO_DIR) -name "*.proto")

.PHONY: gen-proto docker-up docker-down migrate-create migrate-up migrate-down migrate-rollback migrate-version

# --- gRPC gen ---
gen-proto:
	@echo "🔄 Start..."
	mkdir -p $(PKG_DIR)
	@for file in $(PROTO_FILES); do \
		echo "📦 Compile $$file..."; \
		protoc --proto_path=$(PROTO_DIR) \
		       --go_out=$(PKG_DIR) --go_opt=paths=source_relative \
		       --go-grpc_out=$(PKG_DIR) --go-grpc_opt=paths=source_relative \
		       $$file; \
	done
	@echo "✅ Done! All files in /$(PKG_DIR)"

# start all services
docker-up:
	docker-compose -f $(COMPOSE_FILE) --project-directory . up -d

# down DB
docker-down:
	docker-compose -f $(COMPOSE_FILE) --project-directory . down

# new migration (e.g. make migrate-create name=init_schema)
migrate-create:
	migrate create -ext sql -dir $(MIGRATIONS_DIR) -seq $(name)

# apply all
migrate-up:
	migrate -path $(MIGRATIONS_DIR) -database "$(DB_URL)" up

# reset all migrations
migrate-down:
	migrate -path $(MIGRATIONS_DIR) -database "$(DB_URL)" down

# rollback last one
migrate-rollback:
	migrate -path $(MIGRATIONS_DIR) -database "$(DB_URL)" down 1

# current state
migrate-version:
	migrate -path $(MIGRATIONS_DIR) -database "$(DB_URL)" version
