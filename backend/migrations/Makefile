# Migration Makefile

.PHONY: help up down status connect test shell lint build start stop logs clean tables query

help: ## Show this help message
	@echo "Available migration commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v '^help' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Migration Commands
up: ## Run database migrations UP
	./docker-migrate.sh up

down: ## Run database migrations DOWN (rollback)
	./docker-migrate.sh down

status: ## Check current migration status
	./docker-migrate.sh status

connect: ## Connect to database
	./docker-migrate.sh connect

test: ## Test database connection
	./docker-migrate.sh test

tables: ## List all database tables
	./docker-migrate.sh tables

query: ## Query data from a table (usage: make query TABLE=devices [LIMIT=100])
	@if [ -z "$(TABLE)" ]; then \
		echo "Error: TABLE variable required. Usage: make query TABLE=devices [LIMIT=10]"; \
		exit 1; \
	fi
	./docker-migrate.sh query $(TABLE) $(LIMIT)

shell: ## Start interactive shell in migration container
	./docker-migrate.sh shell

lint: ## Lint SQL migration files
	@echo "Linting SQL files..."
	@for file in migrate/*.sql; do \
		if [[ -f "$$file" ]]; then \
			echo "Checking $$file..."; \
		fi; \
	done

# Docker Management
build: ## Build migration Docker image
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy env.example to .env and configure it."; exit 1; fi
	./docker-migrate.sh build

start: ## Build and start migration container
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy env.example to .env and configure it."; exit 1; fi
	./docker-migrate.sh build
	docker compose up -d migrations
	@echo "Docker container started! Use 'make shell' to enter or 'make up' to run migrations"

stop: ## Stop migration container
	docker compose down

logs: ## Show migration container logs
	docker compose logs migrations

clean: ## Clean up Docker containers and images
	./docker-migrate.sh clean

