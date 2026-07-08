IMAGE_NAME ?= sre-student-api
IMAGE_VERSION ?= 1.0.0

# .PHONY tells all args passed to make is an action, not a file.
.PHONY: install run test migrate docker-build docker-run db-start lint migrate-server run-server

# Makefile for managing the SRE Student API project

# Installing dependencies for the project
install:
	uv sync

# Starting the database container if it's not already running, creating the docker network if missing
db-start:
	@echo "Checking if docker network 'sre-network' exists..."
	@docker network inspect sre-network >/dev/null 2>&1 || (echo "Creating 'sre-network'..." && docker network create sre-network)
	@if [ $$(docker ps -q -f name=postgres-db -f status=running | wc -l) -eq 1 ]; then \
		echo "Database container is already running."; \
	else \
		echo "Starting Database container..."; \
		docker compose up -d db; \
	fi


# Running database migrations, checking if the virtual environment exists and using it if available
migrate:
	uv run python migrations/apply_migrations.py

# Running database migrations inside the docker compose environment, ensuring the database is ready before applying migrations
migrate-server: db-start
	@echo "Waiting for database to be ready before migrations..."
	# Using a loop to check if the database is ready, and waiting until it is before proceeding with migrations
	@until docker exec postgres-db pg_isready -U postgres -d students_db >/dev/null 2>&1; do \
		echo "Waiting for database..."; \
		sleep 1; \
	done
	@echo "Running database migrations inside docker compose..."
	# Using docker compose to run the migration script inside the api service, ensuring that the migrations are applied in the correct environment
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose run --rm api migrations/apply_migrations.py

# Running the application, checking if the virtual environment exists and using it if available
run:
	uv run python run.py

# Linting the Dockerfile using hadolint to ensure it follows best practices and standards
lint:
	hadolint Dockerfile

# Running tests, checking if the virtual environment exists and using it if available
test:
	PYTHONPATH=. uv run pytest --ignore=actions-runner -q

# Building the Docker image for the API service using docker compose
docker-build:
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose build api

HOST_LOG_DIR ?= /var/log/sre-student-api

# Running the server locally, ensuring the database is ready and migrations are applied before starting the API service on the host
run-server: db-start # db-start is a prerequisite to ensure the database is running before starting the server
	@echo "Ensuring host log directory exists and is writable by the current user..."
	# Create host log directory and file using sudo since /var/log requires root permissions
	@sudo mkdir -p $(HOST_LOG_DIR) && sudo touch $(HOST_LOG_DIR)/app-server.log
	# Restrict ownership to host user's UID and GID since the server runs directly on the host
	@sudo chown -R $$(id -u):$$(id -g) $(HOST_LOG_DIR)
	# Set 750/640 so only host owner has write/read and group has read permissions
	@sudo chmod 750 $(HOST_LOG_DIR) && sudo chmod 640 $(HOST_LOG_DIR)/app-server.log
	@echo "Checking if database is ready..."
	# Using a loop to check if the database is ready, and waiting until it is before proceeding with starting the API service
	@until docker exec postgres-db pg_isready -U postgres -d students_db >/dev/null 2>&1; do \
		echo "Waiting for database to be ready..."; \
		sleep 1; \
	done
	@echo "Database is ready."
	@echo "Checking if database migrations are already applied..."
	@if docker exec postgres-db psql -U postgres -d students_db -c "\dt" 2>/dev/null | grep -q student; then \
		echo "Database migrations are already applied."; \
		echo "Starting REST API locally..."; \
	else \
		echo "Database migrations not applied. Running migrations..."; \
		$(MAKE) migrate; \
		echo "Starting REST API locally..."; \
	fi
	@export LOG_FILE=$(HOST_LOG_DIR)/app.log && uv run python run.py

# Running the REST API docker container, ensuring the database is ready and migrations are applied before starting the service in docker compose
docker-run: docker-build db-start # db-start & docker-build are prerequisites to ensure the database is running and the Docker image is built before starting the API service
	@echo "Ensuring host log directory exists and has permissions for container user (UID 10001) and Docker daemon group..."
	# Create host log directory and file using sudo since /var/log requires root permissions
	@sudo mkdir -p $(HOST_LOG_DIR) && sudo touch $(HOST_LOG_DIR)/app.log
	# Change owner to 10001 (container user UID) and group to host user's primary group ($(id -g))
	# This allows both container writes and host Docker Desktop VM client mapping without permission conflicts
	@sudo chown -R 10001:$$(id -g) $(HOST_LOG_DIR)
	# Set 770 for directories and 660 for files so owner (container user) and group (host user) can read/write, while blocking others
	@sudo chmod 770 $(HOST_LOG_DIR) && sudo chmod 660 $(HOST_LOG_DIR)/app.log
	@echo "Checking if database is ready..."
	# Using a loop to check if the database is ready, and waiting until it is before proceeding with starting the API service
	@until docker exec postgres-db pg_isready -U postgres -d students_db >/dev/null 2>&1; do \
		echo "Waiting for database to be ready..."; \
		sleep 1; \
	done
	@echo "Database is ready."
	@echo "Checking if database migrations are already applied..."
	@if docker exec postgres-db psql -U postgres -d students_db -c "\dt" 2>/dev/null | grep -q student; then \
		echo "Database migrations are already applied."; \
	else \
		echo "Database migrations not applied. Running migrations..."; \
		$(MAKE) migrate-server; \
	fi
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose up api -d



