IMAGE_NAME ?= sre-student-api
IMAGE_VERSION ?= 1.0.0

# .PHONY tells all args passed to make is an action, not a file.
.PHONY: install run test migrate docker-build docker-run db-start lint migrate-server run-server vagrant-build vagrant-migrate-server vagrant-run vagrant-db-start vault-apply vault-init vault-unseal vault-setup-k8s-auth vault-seed

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
	uv run python src/migrations/apply_migrations.py

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
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose run --rm api src/migrations/apply_migrations.py

# Running the application, checking if the virtual environment exists and using it if available
run:
	uv run python src/run.py

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
	@export LOG_FILE=$(HOST_LOG_DIR)/app.log && uv run python src/run.py

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

vagrant-db-start:
	@echo "Checking if docker network 'sre-network' exists..."
	@docker network inspect sre-network >/dev/null 2>&1 || (echo "Creating 'sre-network'..." && docker network create sre-network)
	@if [ $$(docker ps -q -f name=postgres-db -f status=running | wc -l) -eq 1 ]; then \
		echo "Database container is already running."; \
	else \
		echo "Starting Database container..."; \
		docker compose -f docker-compose.vagrant.yml up -d db; \
	fi

vagrant-build:
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose -f docker-compose.vagrant.yml build

vagrant-migrate-server: vagrant-db-start
	@echo "Waiting for database to be ready before migrations..."
	@until docker exec postgres-db pg_isready -U postgres -d students_db >/dev/null 2>&1; do \
		echo "Waiting for database..."; \
		sleep 1; \
	done
	@echo "Running database migrations inside docker compose..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose -f docker-compose.vagrant.yml run --rm api1 src/migrations/apply_migrations.py

vagrant-run: vagrant-build vagrant-db-start
	@echo "Ensuring host log directory exists and has permissions for container user (UID 10001) and Docker daemon group..."
	@sudo mkdir -p $(HOST_LOG_DIR)/api1 $(HOST_LOG_DIR)/api2
	@sudo touch $(HOST_LOG_DIR)/api1/app.log $(HOST_LOG_DIR)/api2/app.log
	@sudo chown -R 10001:$$(id -g) $(HOST_LOG_DIR)
	@sudo chmod -R 770 $(HOST_LOG_DIR) && sudo chmod 660 $(HOST_LOG_DIR)/api1/app.log $(HOST_LOG_DIR)/api2/app.log
	@echo "Checking if database is ready..."
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
		$(MAKE) vagrant-migrate-server; \
	fi
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose -f docker-compose.vagrant.yml up api1 api2 nginx -d




vault-apply:
	kubectl apply -f hashicorp-vault/ns.yml
	kubectl apply -f hashicorp-vault/sa.yml
	kubectl apply -f hashicorp-vault/configmap.yml
	kubectl apply -f hashicorp-vault/vault-rbac.yml
	kubectl apply -f hashicorp-vault/statefulset.yml
	kubectl apply -f hashicorp-vault/service.yml

vault-init:
	@echo "Initializing Vault..."
	$(eval VAULT_POD := $(shell kubectl get pod -n vault-ns -l app=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null))
	@if [ -z "$(VAULT_POD)" ]; then echo "Vault pod not found!"; exit 1; fi
	kubectl exec -n vault-ns $(VAULT_POD) -- vault operator init -key-shares=1 -key-threshold=1 -format=json > hashicorp-vault/vault-keys.json
	@echo "Vault initialized. Keys saved to hashicorp-vault/vault-keys.json"

vault-unseal:
	$(eval VAULT_POD := $(shell kubectl get pod -n vault-ns -l app=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null))
	@if [ -z "$(VAULT_POD)" ]; then echo "Vault pod not found!"; exit 1; fi
	$(eval UNSEAL_KEY := $(shell python3 -c "import json; d=json.load(open('hashicorp-vault/vault-keys.json')); print(d['unseal_keys_b64'][0])"))
	kubectl exec -n vault-ns $(VAULT_POD) -- vault operator unseal $(UNSEAL_KEY)

vault-setup-k8s-auth:
	$(eval VAULT_POD := $(shell kubectl get pod -n vault-ns -l app=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null))
	@if [ -z "$(VAULT_POD)" ]; then echo "Vault pod not found!"; exit 1; fi
	$(eval ROOT_TOKEN := $(shell python3 -c "import json; d=json.load(open('hashicorp-vault/vault-keys.json')); print(d['root_token'])"))
	kubectl exec -n vault-ns $(VAULT_POD) -- env VAULT_TOKEN=$(ROOT_TOKEN) sh -c '\
	  vault auth enable kubernetes || true; \
	  vault write auth/kubernetes/config \
	    kubernetes_host="https://$$KUBERNETES_SERVICE_HOST:$$KUBERNETES_SERVICE_PORT" \
	    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
	    issuer="https://kubernetes.default.svc.cluster.local" || true; \
	  vault policy write eso-policy - <<EOF\n\
path "kv/data/org/*" { capabilities = ["read"] }\n\
EOF\n\
	  vault write auth/kubernetes/role/eso-role \
	    bound_service_account_names=external-secrets \
	    bound_service_account_namespaces=external-secrets-ns \
	    policies=eso-policy \
	    ttl=1h'

vault-seed:
	$(eval VAULT_POD := $(shell kubectl get pod -n vault-ns -l app=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null))
	@if [ -z "$(VAULT_POD)" ]; then echo "Vault pod not found!"; exit 1; fi
	$(eval ROOT_TOKEN := $(shell python3 -c "import json; d=json.load(open('hashicorp-vault/vault-keys.json')); print(d['root_token'])"))
	kubectl exec -n vault-ns $(VAULT_POD) -- env VAULT_TOKEN=$(ROOT_TOKEN) sh -c '\
	  vault secrets enable -path=kv kv-v2 || true; \
	  vault kv put kv/org/dev POSTGRES_PASSWORD="changeme" database_url="postgresql://postgres:changeme@postgres-db.student-api.svc.cluster.local:5432/students_db" || true'
