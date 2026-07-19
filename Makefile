IMAGE_NAME ?= sre-student-api
IMAGE_VERSION ?= 1.0.0
COMPOSE_CMD ?= docker compose
HOST_LOG_DIR ?= /var/log/sre-student-api
PORT ?= 5001

.PHONY: install run test migrate docker-build docker-run db-start lint migrate-server run-server \
        vagrant-build vagrant-migrate-server vagrant-run vagrant-db-start \
        vault-apply vault-init vault-unseal vault-setup-k8s-auth vault-seed \
        ensure-network wait-db setup-host-logs

# Installing dependencies for the project
install:
	uv sync

# Ensure docker network exists
ensure-network:
	@echo "Checking if docker network 'sre-network' exists..."
	@docker network inspect sre-network >/dev/null 2>&1 || (echo "Creating 'sre-network'..." && docker network create sre-network)

# Starting the database container if it's not already running
db-start: ensure-network
	@if [ $$(docker ps -q -f name=postgres-db -f status=running | wc -l) -eq 1 ]; then \
		echo "Database container is already running."; \
	else \
		echo "Starting Database container..."; \
		$(COMPOSE_CMD) up -d db; \
	fi

# Vagrant database startup target overriding compose command
vagrant-db-start:
	@$(MAKE) db-start COMPOSE_CMD="docker compose -f docker-compose.vagrant.yml"

# Wait for postgres database readiness
wait-db:
	@echo "Checking if database is ready..."
	@until docker exec postgres-db pg_isready -U postgres -d students_db >/dev/null 2>&1; do \
		echo "Waiting for database to be ready..."; \
		sleep 1; \
	done
	@echo "Database is ready."

# Running database migrations locally using Alembic
migrate:
	@echo "Applying database schema migrations locally with Alembic..."
	uv run alembic upgrade head

# Running database migrations inside the docker compose environment using Alembic
migrate-server: db-start wait-db
	@echo "Running database schema migrations inside docker compose with Alembic..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose run --rm api alembic upgrade head

vagrant-migrate-server: vagrant-db-start wait-db
	@echo "Running database schema migrations inside docker compose (vagrant) with Alembic..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose -f docker-compose.vagrant.yml run --rm api1 alembic upgrade head

# Running the application locally
run:
	PORT=$(PORT) PYTHONPATH=. uv run python src/run.py

# Linting the Dockerfile
lint:
	hadolint Dockerfile

# Running tests
test:
	PYTHONPATH=. uv run pytest --ignore=actions-runner -q

# Building the Docker image
docker-build:
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose build api

vagrant-build:
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose -f docker-compose.vagrant.yml build

# Setup host logs with dynamically resolved container user permissions
setup-host-logs:
	@echo "Ensuring host log directories exist..."
	@sudo mkdir -p $(HOST_LOG_DIR) $(HOST_LOG_DIR)/api1 $(HOST_LOG_DIR)/api2
	@sudo touch $(HOST_LOG_DIR)/app.log $(HOST_LOG_DIR)/api1/app.log $(HOST_LOG_DIR)/api2/app.log
	@echo "Fetching container UID and GID dynamically..."
	@CONTAINER_UID=$$(docker run --rm --entrypoint id sre-student-api:$(IMAGE_VERSION) -u 2>/dev/null || echo 1000); \
	CONTAINER_GID=$$(docker run --rm --entrypoint id sre-student-api:$(IMAGE_VERSION) -g 2>/dev/null || echo 1000); \
	sudo chown -R $$CONTAINER_UID:$$CONTAINER_GID $(HOST_LOG_DIR)
	@sudo chmod -R 777 $(HOST_LOG_DIR)
	@sudo chmod 660 $(HOST_LOG_DIR)/app.log $(HOST_LOG_DIR)/api1/app.log $(HOST_LOG_DIR)/api2/app.log

# Running the server locally
run-server: db-start wait-db
	@echo "Ensuring host log directory exists and is writable by the current user..."
	@sudo mkdir -p $(HOST_LOG_DIR) && sudo touch $(HOST_LOG_DIR)/app-server.log
	@sudo chown -R $$(id -u):$$(id -g) $(HOST_LOG_DIR)
	@sudo chmod 750 $(HOST_LOG_DIR) && sudo chmod 640 $(HOST_LOG_DIR)/app-server.log
	@echo "Applying migrations..."
	@$(MAKE) migrate
	@echo "Starting REST API locally..."
	@export LOG_FILE=$(HOST_LOG_DIR)/app.log && PORT=$(PORT) PYTHONPATH=. uv run python src/run.py

# Running the REST API docker container
docker-run: docker-build db-start setup-host-logs wait-db
	@echo "Starting REST API container via docker compose..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose up api -d

# Running the vagrant target compose api cluster
vagrant-run: vagrant-build vagrant-db-start setup-host-logs wait-db
	@echo "Starting vagrant cluster via docker compose..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose -f docker-compose.vagrant.yml up api1 api2 nginx -d


# HashiCorp Vault Targets
vault-apply:
	@echo "Applying HashiCorp Vault Kubernetes manifests..."
	kubectl apply -f hashicorp-vault/h-vault.yml

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
	  vault secrets enable -path=secret kv-v2 || true; \
	  vault kv patch secret/one2n/dev/app-config \
	    db_password="changeme" \
	    db_url="postgresql://postgres:changeme@postgres-db.student-api.svc.cluster.local:5432/students_db" \
	    database_url="postgresql://postgres:changeme@postgres-db.student-api.svc.cluster.local:5432/students_db" \
	    dockerconfigjson="{\"auths\":{\"https://index.docker.io/v1/\":{\"username\":\"wakharemadhav\",\"password\":\"changeme\"}}}" || true'
