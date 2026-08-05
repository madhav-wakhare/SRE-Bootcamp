# =============================================================================
# Global variables (shared across every section below)
# =============================================================================
IMAGE_NAME ?= sre-student-api
IMAGE_VERSION ?= 1.0.0
COMPOSE_CMD ?= docker compose
HOST_LOG_DIR ?= /var/log/sre-student-api
PORT ?= 5001
# Shared between section 4 (plain manifests) and section 5 (Helm) below --
# both deploy the same application namespace, just via different tooling.
APP_NS ?= student-api

# =============================================================================
# 1. Running the server locally
# =============================================================================
# The API process itself runs directly on the host (`uv run python ...`), not
# in a container. The database can be a fully local Postgres/SQLite (plain
# `install` -> `migrate` -> `run`) or the Docker Compose-managed Postgres
# container (`run-server`, which only containerizes the database).
.PHONY: install test migrate run ensure-network db-start wait-db run-server

# Installing dependencies for the project
install:
	uv sync

# Running tests
test:
	PYTHONPATH=. uv run pytest --ignore=actions-runner -q

# Running database migrations locally using Alembic
migrate:
	@echo "Applying database schema migrations locally with Alembic..."
	uv run alembic upgrade head

# Running the application locally
run:
	PORT=$(PORT) PYTHONPATH=. uv run python src/run.py

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

# Wait for postgres database readiness
wait-db:
	@echo "Checking if database is ready..."
	@until docker exec postgres-db pg_isready -U postgres -d students_db >/dev/null 2>&1; do \
		echo "Waiting for database to be ready..."; \
		sleep 1; \
	done
	@echo "Database is ready."

# Running the server locally, with its database supplied by Docker Compose
run-server: db-start wait-db
	@echo "Ensuring host log directory exists and is writable by the current user..."
	@sudo mkdir -p $(HOST_LOG_DIR) && sudo touch $(HOST_LOG_DIR)/app-server.log
	@sudo chown -R $$(id -u):$$(id -g) $(HOST_LOG_DIR)
	@sudo chmod 750 $(HOST_LOG_DIR) && sudo chmod 640 $(HOST_LOG_DIR)/app-server.log
	@echo "Applying migrations..."
	@$(MAKE) migrate
	@echo "Starting REST API locally..."
	@export LOG_FILE=$(HOST_LOG_DIR)/app.log && PORT=$(PORT) PYTHONPATH=. uv run python src/run.py

# =============================================================================
# 2. Running via Docker Compose (containerized)
# =============================================================================
# Both the app and its migrations run inside containers here, unlike
# `run-server` above where only the database is containerized.
.PHONY: lint migrate-server docker-build setup-host-logs docker-run

# Linting the Dockerfile
lint:
	hadolint Dockerfile

# Running database migrations inside the docker compose environment using Alembic
migrate-server: db-start wait-db
	@echo "Running database schema migrations inside docker compose with Alembic..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose run --rm api alembic upgrade head

# Building the Docker image
docker-build:
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose build api

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

# Running the REST API docker container
docker-run: docker-build db-start setup-host-logs wait-db
	@echo "Starting REST API container via docker compose..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose up api -d

# =============================================================================
# 3. Running via Vagrant (multi-VM, load-balanced Nginx + 2 API instances)
# =============================================================================
.PHONY: vagrant-build vagrant-db-start vagrant-migrate-server vagrant-run

vagrant-build:
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose -f docker-compose.vagrant.yml build

# Vagrant database startup target overriding compose command
vagrant-db-start:
	@$(MAKE) db-start COMPOSE_CMD="docker compose -f docker-compose.vagrant.yml"

vagrant-migrate-server: vagrant-db-start wait-db
	@echo "Running database schema migrations inside docker compose (vagrant) with Alembic..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose -f docker-compose.vagrant.yml run --rm api1 alembic upgrade head

# Running the vagrant target compose api cluster
vagrant-run: vagrant-build vagrant-db-start setup-host-logs wait-db
	@echo "Starting vagrant cluster via docker compose..."
	IMAGE_NAME=$(IMAGE_NAME) IMAGE_VERSION=$(IMAGE_VERSION) docker compose -f docker-compose.vagrant.yml up api1 api2 nginx -d

# =============================================================================
# Kubernetes cluster (Minikube) -- shared prerequisite for sections 4 and 5
# =============================================================================
# A dedicated, cordoned control-plane plus three labeled worker nodes -- one
# per responsibility. The control-plane runs no application workload, so
# "three nodes for three jobs" refers to the three workers; the control-plane
# is a fourth, infrastructure-only node.
.PHONY: k8s-cluster-up k8s-cluster-label k8s-cluster-status k8s-cluster-down

MINIKUBE_PROFILE     ?= minikube
MINIKUBE_DRIVER      ?= docker
MINIKUBE_NODES       ?= 4
MINIKUBE_CPUS        ?= 2
MINIKUBE_MEMORY      ?= 3072

# Node -> role mapping. Minikube names additional nodes <profile>-m02, -m03, ...
# in creation order; only the three workers get a `type` label, so nothing can
# schedule onto the control-plane by accident even if it were later uncordoned.
NODE_APP             ?= $(MINIKUBE_PROFILE)-m04
NODE_DB              ?= $(MINIKUBE_PROFILE)-m02
NODE_DEPENDENT_SVCS  ?= $(MINIKUBE_PROFILE)-m03

# Creates the cluster on first run; on every later run it just verifies the
# profile is up, since `minikube start` only provisions nodes once per profile
# (the --nodes count is ignored on an existing profile).
k8s-cluster-up:
	@echo "Starting Minikube profile '$(MINIKUBE_PROFILE)' ($(MINIKUBE_NODES) nodes, driver=$(MINIKUBE_DRIVER))..."
	minikube start -p $(MINIKUBE_PROFILE) \
		--nodes=$(MINIKUBE_NODES) \
		--driver=$(MINIKUBE_DRIVER) \
		--cpus=$(MINIKUBE_CPUS) \
		--memory=$(MINIKUBE_MEMORY)
	@$(MAKE) k8s-cluster-label

# Cordons the control-plane and labels each worker with its role. Both
# `kubectl cordon` and `kubectl label --overwrite` are idempotent, so this is
# safe to re-run any time, e.g. after `minikube start` recreates a stopped node.
k8s-cluster-label:
	@echo "Cordoning control-plane node ($(MINIKUBE_PROFILE)) -- no application workload runs there..."
	kubectl cordon $(MINIKUBE_PROFILE)
	@echo "Labeling worker nodes with their role..."
	kubectl label node $(NODE_APP)            type=application       --overwrite
	kubectl label node $(NODE_DB)              type=database           --overwrite
	kubectl label node $(NODE_DEPENDENT_SVCS)  type=dependent_services --overwrite
	@echo "Done. Verify with: make k8s-cluster-status"

k8s-cluster-status:
	@echo "--- Nodes (role label, schedulability, k8s version) ---"
	@kubectl get nodes -L type -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,ROLE:.metadata.labels.node-role\.kubernetes\.io/control-plane,TYPE:.metadata.labels.type,VERSION:.status.nodeInfo.kubeletVersion'
	@echo ""
	@echo "--- Taints (control-plane should show node.kubernetes.io/unschedulable) ---"
	@kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key'

# Deletes the whole cluster and everything deployed on it (all namespaces, all
# Helm releases, all PVC-backed data). Never wired into another target's
# dependencies -- must be invoked explicitly.
k8s-cluster-down:
	@echo "WARNING: this deletes the '$(MINIKUBE_PROFILE)' Minikube cluster and everything running on it."
	minikube delete -p $(MINIKUBE_PROFILE)

# =============================================================================
# 4. Running via plain Kubernetes manifests (historical reference only)
# =============================================================================
# Superseded by Helm (section 5 below). The raw manifests under k8s/ and
# hashicorp-vault/ are kept only for reference and must not be applied
# alongside the Helm releases. There is deliberately no "deploy" target here
# any more -- only the teardown needed once, to hand the namespace to Helm.
.PHONY: k8s-manifest-teardown

# Removes the older kubectl-managed stack from the previous milestone. Helm
# refuses to adopt resources it did not create, so this has to run once before
# the first `make helm-install-all`.
k8s-manifest-teardown:
	@echo "WARNING: deleting the kubectl-managed stack (namespaces $(APP_NS) and vault-ns)."
	kubectl delete -f k8s/es-operator/ --ignore-not-found || true
	kubectl delete namespace $(APP_NS) --ignore-not-found
	kubectl delete namespace vault-ns --ignore-not-found
	@echo "Done. The Helm releases will recreate $(APP_NS) from scratch."

# =============================================================================
# 5. Running via Helm
# =============================================================================
# Chart location and one release per component. Release names deliberately match
# the chart names so the generated resource names stay short and predictable
# (e.g. release "postgres-db" of chart "postgres-db" -> service "postgres-db").
.PHONY: helm-legacy-cleanup helm-deps helm-lint helm-template helm-package argocd-validate \
        helm-install-eso-operator helm-install-vault \
        vault-status vault-init vault-unseal vault-configure vault-seed vault-setup helm-vault-reset \
        helm-install-eso-config helm-install-postgres helm-install-student-api helm-install-all \
        helm-status helm-verify helm-uninstall-all

HELM_DIR        ?= helm
VAULT_NS        ?= vault
ESO_NS          ?= eso-ns
VAULT_RELEASE   ?= vault
ESO_RELEASE     ?= external-secrets
ESO_CFG_RELEASE ?= eso-config
DB_RELEASE      ?= postgres-db
API_RELEASE     ?= student-api
CHART_DIST      ?= dist
# Local port for the helm-verify healthcheck tunnel (see below).
HEALTHCHECK_LOCAL_PORT ?= 15000

# Vault bootstrap. The keys file is gitignored -- it holds the unseal key and the
# root token, so never commit it.
VAULT_KEYS    ?= hashicorp-vault/vault-keys.json
VAULT_KV_MOUNT?= secret
VAULT_KV_PATH ?= one2n/dev/app-config
VAULT_POD      = $(VAULT_RELEASE)-0

# Seed values written into Vault. Override on the command line for a real
# environment, e.g. `make vault-seed DB_PASSWORD=$$(openssl rand -hex 16)`.
DB_USER     ?= postgres
DB_NAME     ?= students_db
DB_PASSWORD ?= postgres
# Must resolve to the postgres-db chart's service in the application namespace.
DB_HOST      = $(DB_RELEASE).$(APP_NS).svc.cluster.local
DATABASE_URL_VALUE = postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):5432/$(DB_NAME)

# Reads a field out of the keys file produced by `make vault-init`.
VAULT_JSON = python3 -c "import json,sys; print(json.load(open('$(VAULT_KEYS)'))[sys.argv[1]] if sys.argv[1]=='root_token' else json.load(open('$(VAULT_KEYS)'))['unseal_keys_b64'][0])"

# -----------------------------------------------------------------------------
# Pre-flight: remove releases left over from earlier chart iterations, whose
# resource names differ from the current ones and would otherwise collide
# (e.g. release "v" with its "vault-statefulset" and "vault-config"). Run this
# once before the first `make helm-install-all` if migrating from an older
# version of these charts.
# -----------------------------------------------------------------------------
helm-legacy-cleanup:
	@echo "Removing Helm releases from earlier chart iterations..."
	@helm list --all-namespaces -o json \
		| python3 -c "import json,sys; print('\n'.join(r['name']+' '+r['namespace'] for r in json.load(sys.stdin) if r['name'] in {'v','ev','eso-backend','student-app','app'}))" \
		| while read rel ns; do \
			[ -z "$$rel" ] && continue; \
			echo "  uninstalling $$rel from $$ns"; \
			helm uninstall $$rel -n $$ns || true; \
		done
	kubectl delete pvc vault-data-vault-statefulset-0 -n $(VAULT_NS) --ignore-not-found
	kubectl delete clustersecretstore ev-vault-one2n-store v-vault-one2n-store vault-one2n-store --ignore-not-found
	@echo "Done."

# -----------------------------------------------------------------------------
# Chart maintenance
# -----------------------------------------------------------------------------
# Vendors the upstream External Secrets Operator chart into
# helm/external-secrets/charts/. Only needed after editing its Chart.yaml.
helm-deps:
	@echo "Building chart dependencies..."
	helm dependency build $(HELM_DIR)/external-secrets
	helm dependency build $(HELM_DIR)/argocd

helm-lint:
	@echo "Linting all Helm charts..."
	helm lint $(HELM_DIR)/external-secrets
	helm lint $(HELM_DIR)/vault
	helm lint $(HELM_DIR)/eso-config
	helm lint $(HELM_DIR)/postgres-db
	helm lint $(HELM_DIR)/student-api
	helm lint $(HELM_DIR)/argocd

# $(ARGOCD_DIR)/ is plain YAML, not a Helm chart -- validate it against the
# live cluster's API schema the same way, just without a `helm template` step.
argocd-validate:
	@echo "Validating $(ARGOCD_DIR)/*.yaml against the cluster's API schema..."
	kubectl apply --dry-run=server -f $(ARGOCD_DIR)/

# Renders every chart and validates it against the live cluster's API schema
# without applying anything.
helm-template:
	helm template $(VAULT_RELEASE) $(HELM_DIR)/vault -n $(VAULT_NS) | kubectl apply -n $(VAULT_NS) --dry-run=server -f -
	helm template $(ESO_CFG_RELEASE) $(HELM_DIR)/eso-config -n $(ESO_NS) | kubectl apply -n $(ESO_NS) --dry-run=server -f -
	helm template $(DB_RELEASE) $(HELM_DIR)/postgres-db -n $(APP_NS) | kubectl apply -n $(APP_NS) --dry-run=server -f -
	helm template $(API_RELEASE) $(HELM_DIR)/student-api -n $(APP_NS) | kubectl apply -n $(APP_NS) --dry-run=server -f -

helm-package:
	@echo "Packaging all Helm charts into $(CHART_DIST)/..."
	@mkdir -p $(CHART_DIST)
	helm package $(HELM_DIR)/external-secrets --destination $(CHART_DIST)/
	helm package $(HELM_DIR)/vault --destination $(CHART_DIST)/
	helm package $(HELM_DIR)/eso-config --destination $(CHART_DIST)/
	helm package $(HELM_DIR)/postgres-db --destination $(CHART_DIST)/
	helm package $(HELM_DIR)/student-api --destination $(CHART_DIST)/
	helm package $(HELM_DIR)/argocd --destination $(CHART_DIST)/

# -----------------------------------------------------------------------------
# Install, one component per target, in dependency order
# -----------------------------------------------------------------------------
# 1. The operator plus its CRDs. Must exist before any ExternalSecret or
#    ClusterSecretStore can be created.
helm-install-eso-operator:
	@echo "Installing External Secrets Operator in namespace $(ESO_NS)..."
	helm upgrade --install $(ESO_RELEASE) $(HELM_DIR)/external-secrets \
		--namespace $(ESO_NS) --create-namespace \
		--wait --timeout 5m

# 2. Vault, the secret backend. Starts up sealed and empty -- the vault-* Vault
#    bootstrap targets right below finish setting it up before anything reads
#    from it.
helm-install-vault:
	@echo "Deploying HashiCorp Vault in namespace $(VAULT_NS)..."
	helm upgrade --install $(VAULT_RELEASE) $(HELM_DIR)/vault \
		--namespace $(VAULT_NS) --create-namespace \
		--wait --timeout 5m

# -----------------------------------------------------------------------------
# Vault bootstrap (operates on the Helm-deployed Vault above)
# -----------------------------------------------------------------------------
vault-status:
	kubectl exec -n $(VAULT_NS) $(VAULT_POD) -c vault -- vault status || true

# Initialises Vault with a single unseal key (fine for a dev cluster; production
# wants the key split across several holders). Skipped if already initialised.
vault-init:
	@if kubectl exec -n $(VAULT_NS) $(VAULT_POD) -c vault -- vault status -format=json 2>/dev/null | grep -q '"initialized": true'; then \
		echo "Vault is already initialized, skipping."; \
	else \
		echo "Initializing Vault, keys go to $(VAULT_KEYS)..."; \
		mkdir -p $$(dirname $(VAULT_KEYS)); \
		kubectl exec -n $(VAULT_NS) $(VAULT_POD) -c vault -- \
			vault operator init -key-shares=1 -key-threshold=1 -format=json > $(VAULT_KEYS); \
		echo "Done. $(VAULT_KEYS) holds the unseal key and root token, keep it out of git."; \
	fi

# Vault seals itself on every restart, so this is expected to be re-run.
vault-unseal:
	@test -s $(VAULT_KEYS) || { echo "$(VAULT_KEYS) is missing or empty. Run 'make vault-init' first."; exit 1; }
	@if kubectl exec -n $(VAULT_NS) $(VAULT_POD) -c vault -- vault status -format=json 2>/dev/null | grep -q '"sealed": false'; then \
		echo "Vault is already unsealed, skipping."; \
	else \
		echo "Unsealing Vault..."; \
		kubectl exec -n $(VAULT_NS) $(VAULT_POD) -c vault -- \
			vault operator unseal "$$($(VAULT_JSON) unseal_key)" >/dev/null; \
		echo "Vault unsealed."; \
	fi

# Enables the KV v2 engine and the Kubernetes auth role ESO logs in with. The
# bound service account must match the one the ESO chart creates, and the policy
# must grant read on the exact KV path the ExternalSecrets reference.
vault-configure:
	@test -s $(VAULT_KEYS) || { echo "$(VAULT_KEYS) is missing or empty. Run 'make vault-init' first."; exit 1; }
	@echo "Configuring Vault: KV v2 engine, Kubernetes auth, ESO policy and role..."
	@kubectl exec -n $(VAULT_NS) $(VAULT_POD) -c vault -- \
		env VAULT_TOKEN="$$($(VAULT_JSON) root_token)" sh -c '\
		  vault secrets enable -path=$(VAULT_KV_MOUNT) -version=2 kv 2>/dev/null || echo "  KV engine already enabled"; \
		  vault auth enable kubernetes 2>/dev/null || echo "  kubernetes auth already enabled"; \
		  vault write auth/kubernetes/config \
		    kubernetes_host="https://$$KUBERNETES_SERVICE_HOST:$$KUBERNETES_SERVICE_PORT" \
		    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
		    issuer="https://kubernetes.default.svc.cluster.local"; \
		  echo "path \"$(VAULT_KV_MOUNT)/data/$(VAULT_KV_PATH)\" { capabilities = [\"read\"] }" \
		    | vault policy write eso-policy -; \
		  vault write auth/kubernetes/role/eso-role \
		    bound_service_account_names=external-secrets \
		    bound_service_account_namespaces=$(ESO_NS) \
		    policies=eso-policy ttl=24h'
	@echo "Vault configured."

# Writes the application secrets. db_url embeds the in-cluster DNS name of the
# postgres-db service, so it must be reseeded if that release is renamed.
vault-seed:
	@test -s $(VAULT_KEYS) || { echo "$(VAULT_KEYS) is missing or empty. Run 'make vault-init' first."; exit 1; }
	@echo "Seeding $(VAULT_KV_MOUNT)/$(VAULT_KV_PATH)..."
	@kubectl exec -n $(VAULT_NS) $(VAULT_POD) -c vault -- \
		env VAULT_TOKEN="$$($(VAULT_JSON) root_token)" \
		vault kv put $(VAULT_KV_MOUNT)/$(VAULT_KV_PATH) \
		  db_password="$(DB_PASSWORD)" \
		  db_url="$(DATABASE_URL_VALUE)"
	@echo "Seeded. db_url points at $(DB_HOST):5432/$(DB_NAME)"

# Everything Vault needs after `make helm-install-vault`.
vault-setup: vault-init vault-unseal vault-configure vault-seed

# Wipes Vault's storage and redeploys it. Use when Vault is initialised but the
# keys file has been lost, which makes it permanently unsealable.
helm-vault-reset:
	@echo "WARNING: this deletes all Vault data, including the seeded secrets."
	helm uninstall $(VAULT_RELEASE) --namespace $(VAULT_NS) || true
	kubectl delete pvc data-$(VAULT_POD) -n $(VAULT_NS) --ignore-not-found
	rm -f $(VAULT_KEYS)
	@$(MAKE) helm-install-vault
	@$(MAKE) vault-setup

# 3. The ClusterSecretStore that points ESO at Vault. Needs an unsealed Vault
#    with the Kubernetes auth role already configured, or it reports NotReady.
helm-install-eso-config:
	@echo "Deploying ClusterSecretStore in namespace $(ESO_NS)..."
	helm upgrade --install $(ESO_CFG_RELEASE) $(HELM_DIR)/eso-config \
		--namespace $(ESO_NS) --create-namespace \
		--wait --timeout 2m

# 4. PostgreSQL. Its password is synced out of Vault by ESO.
helm-install-postgres:
	@echo "Deploying PostgreSQL in namespace $(APP_NS)..."
	helm upgrade --install $(DB_RELEASE) $(HELM_DIR)/postgres-db \
		--namespace $(APP_NS) --create-namespace \
		--wait --timeout 5m

# 5. The REST API. Its initContainer applies migrations before it serves traffic.
helm-install-student-api:
	@echo "Deploying Student REST API in namespace $(APP_NS)..."
	helm upgrade --install $(API_RELEASE) $(HELM_DIR)/student-api \
		--namespace $(APP_NS) --create-namespace \
		--wait --timeout 5m

# One command for the whole stack, in order, including the Vault bootstrap.
# Safe to re-run: every step is idempotent.
helm-install-all: helm-install-eso-operator helm-install-vault vault-setup helm-install-eso-config helm-install-postgres helm-install-student-api
	@echo ""
	@echo "==========================================================="
	@echo "Stack deployed. Verify with: make helm-verify"
	@echo "==========================================================="

# -----------------------------------------------------------------------------
# Verify and tear down
# -----------------------------------------------------------------------------
helm-status:
	@helm list --all-namespaces

helm-verify:
	@echo "--- Helm releases ---"
	@helm list --all-namespaces
	@echo ""
	@echo "--- Vault ---"
	@kubectl get pods -n $(VAULT_NS)
	@echo ""
	@echo "--- ClusterSecretStore (READY must be True) ---"
	@kubectl get clustersecretstore
	@echo ""
	@echo "--- ExternalSecrets (STATUS must be SecretSynced) ---"
	@kubectl get externalsecret -n $(APP_NS)
	@echo ""
	@echo "--- Application namespace ---"
	@kubectl get pods,svc -n $(APP_NS)
	@echo ""
	@echo "--- Healthcheck (via kubectl port-forward) ---"
	@echo "(NodePort is not used here: the Minikube docker driver on macOS never"
	@echo " exposes it to the host -- only a fixed port set is docker-published"
	@echo " per node, see 'docker ps'. A tunnel is the portable way to reach it.)"
	@SVC_PORT=$$(kubectl get svc $(API_RELEASE) -n $(APP_NS) -o jsonpath='{.spec.ports[0].port}'); \
	kubectl port-forward -n $(APP_NS) svc/$(API_RELEASE) $(HEALTHCHECK_LOCAL_PORT):$$SVC_PORT >/tmp/helm-verify-portforward.log 2>&1 & \
	PF_PID=$$!; \
	trap "kill $$PF_PID >/dev/null 2>&1" EXIT; \
	sleep 2; \
	echo "GET http://localhost:$(HEALTHCHECK_LOCAL_PORT)/healthcheck"; \
	curl -sS --max-time 10 "http://localhost:$(HEALTHCHECK_LOCAL_PORT)/healthcheck" \
		|| echo "  (unreachable -- check 'kubectl logs -n $(APP_NS) deploy/$(API_RELEASE)' and /tmp/helm-verify-portforward.log)"; \
	echo

helm-uninstall-all:
	@echo "Uninstalling all Helm releases..."
	helm uninstall $(API_RELEASE) --namespace $(APP_NS) || true
	helm uninstall $(DB_RELEASE) --namespace $(APP_NS) || true
	helm uninstall $(ESO_CFG_RELEASE) --namespace $(ESO_NS) || true
	helm uninstall $(VAULT_RELEASE) --namespace $(VAULT_NS) || true
	helm uninstall $(ESO_RELEASE) --namespace $(ESO_NS) || true
	@echo "PVCs are kept on purpose. Delete them explicitly to discard the data:"
	@echo "  kubectl delete pvc -n $(APP_NS) --all"
	@echo "  kubectl delete pvc -n $(VAULT_NS) --all"

# =============================================================================
# 6. GitOps with Argo CD
# =============================================================================
# After bootstrapping, `helm upgrade` is no longer how this stack is deployed:
# Argo CD watches the charts under helm/ on ARGOCD_REVISION and applies them
# itself. The section 5 targets above stay useful for linting, templating, and
# for the one-time bootstrap of a cluster that has no Argo CD yet.
.PHONY: argocd-install argocd-apps-install argocd-bootstrap argocd-status \
        argocd-password argocd-ui argocd-refresh argocd-verify \
        argocd-uninstall helm-set-image-tag

ARGOCD_NS            ?= argocd
ARGOCD_RELEASE       ?= argocd
# Plain-YAML manifests applied with kubectl -- see argocd-apps/README.md.
ARGOCD_DIR           ?= argocd-apps
# Branch (or tag/commit) Argo CD tracks. Override to deploy from a feature
# branch, e.g. `make argocd-bootstrap ARGOCD_REVISION=k8s`.
ARGOCD_REVISION      ?= main
# Local port for `make argocd-ui`. The NodePort of a Minikube docker-driver node
# is not reachable from the host on macOS, so the UI is port-forwarded too.
ARGOCD_UI_PORT       ?= 8090

# 1. Argo CD itself. This is the only component that is not GitOps-managed --
#    something has to deploy the deployer.
argocd-install:
	@echo "Installing Argo CD in namespace $(ARGOCD_NS) (pinned to the dependent_services node)..."
	helm upgrade --install $(ARGOCD_RELEASE) $(HELM_DIR)/argocd \
		--namespace $(ARGOCD_NS) --create-namespace \
		--wait --timeout 10m

# 2. The declarative Argo CD configuration: AppProject, repository Secret, one
#    Application per chart, and the root app that keeps them synced from git.
#    Plain kubectl apply -- no Helm release, no values.yaml. targetRevision is
#    hardcoded to "main" in every file; the sed below overrides it on the fly
#    for `make argocd-apps-install ARGOCD_REVISION=<branch>` without touching
#    the files on disk.
argocd-apps-install:
	@echo "Applying Argo CD configuration (revision: $(ARGOCD_REVISION)) from $(ARGOCD_DIR)/..."
	sed -E 's|^(    targetRevision: ).*|\1$(ARGOCD_REVISION)|' $(ARGOCD_DIR)/*.yaml | kubectl apply -f -

# One command to hand the cluster over to GitOps.
argocd-bootstrap: argocd-install argocd-apps-install
	@echo ""
	@echo "==========================================================="
	@echo "Argo CD is bootstrapped and syncing from $(ARGOCD_REVISION)."
	@echo "  make argocd-status    # watch the Applications converge"
	@echo "  make argocd-ui        # open the UI"
	@echo "Vault still needs its one-time bootstrap: make vault-setup"
	@echo "==========================================================="

argocd-status:
	@echo "--- Argo CD pods (all must be on $(NODE_DEPENDENT_SVCS)) ---"
	@kubectl get pods -n $(ARGOCD_NS) -o wide
	@echo ""
	@echo "--- Applications ---"
	@kubectl get applications -n $(ARGOCD_NS)

# Argo CD generates the initial admin password into a Secret on first install.
argocd-password:
	@kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo

argocd-ui:
	@echo "Argo CD UI: http://localhost:$(ARGOCD_UI_PORT)  (user: admin, password: make argocd-password)"
	kubectl port-forward -n $(ARGOCD_NS) svc/argocd-server $(ARGOCD_UI_PORT):80

# Forces an immediate re-poll of git instead of waiting for the reconciliation
# interval. Useful right after a push when demoing the pipeline.
argocd-refresh:
	@for app in $$(kubectl get applications -n $(ARGOCD_NS) -o name); do \
		kubectl patch $$app -n $(ARGOCD_NS) --type merge \
			-p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' >/dev/null; \
		echo "refresh requested: $$app"; \
	done

# The GitOps equivalent of `make helm-verify`: what git says, what the cluster
# runs, and whether the two agree.
argocd-verify:
	@echo "--- Applications (SYNC and HEALTH must both be Synced / Healthy) ---"
	@kubectl get applications -n $(ARGOCD_NS) \
		-o custom-columns='NAME:.metadata.name,REVISION:.spec.source.targetRevision,PATH:.spec.source.path,SYNC:.status.sync.status,HEALTH:.status.health.status,AT:.status.operationState.finishedAt'
	@echo ""
	@echo "--- Image tag: git vs cluster ---"
	@echo "  values.yaml: $$(awk '/^image:/{f=1} f&&/^[^ #]/&&!/^image:/{f=0} f&&$$1=="tag:"{gsub(/"/,"",$$2); print $$2; exit}' $(HELM_DIR)/student-api/values.yaml)"
	@echo "  running    : $$(kubectl get deploy $(API_RELEASE) -n $(APP_NS) -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')"
	@echo ""
	@$(MAKE) --no-print-directory helm-verify

# Removes Argo CD without taking the deployed stack down with it: the
# Applications carry a resources-finalizer, so deleting them while the finalizer
# is in place would cascade into every workload they manage.
argocd-uninstall:
	@echo "Dropping Application finalizers so the workloads are orphaned, not deleted..."
	@for app in $$(kubectl get applications -n $(ARGOCD_NS) -o name 2>/dev/null); do \
		kubectl patch $$app -n $(ARGOCD_NS) --type merge \
			-p '{"metadata":{"finalizers":null}}' >/dev/null || true; \
	done
	kubectl delete -f $(ARGOCD_DIR)/ --ignore-not-found
	helm uninstall $(ARGOCD_RELEASE) --namespace $(ARGOCD_NS) || true
	@echo "Done. The stack keeps running, but nothing reconciles it any more."

# -----------------------------------------------------------------------------
# The CI-side half of the loop
# -----------------------------------------------------------------------------
# What the "update-image-tag" job in .github/workflows/ci.yml runs -- the job
# calls this target, so the edit is defined in exactly one place and can be made
# and reviewed locally too:
#   make helm-set-image-tag TAG=$(git rev-parse --short=7 HEAD)
#
# The `^  tag: ` anchor matters: it pins the replacement to the two-space
# indented key inside the top-level `image:` block, so nothing else in the file
# can be hit by accident. sed -i.bak (rather than a bare -i) is the spelling
# that works on both BSD sed (the macOS runner) and GNU sed.
helm-set-image-tag: VALUES = $(HELM_DIR)/student-api/values.yaml
helm-set-image-tag:
	@test -n "$(TAG)" || { echo "usage: make helm-set-image-tag TAG=<image-tag>"; exit 1; }
	@grep -qE '^  tag: ' $(VALUES) || { echo "no 'tag:' key found in $(VALUES)"; exit 1; }
	@sed -i.bak -E 's|^(  tag: ).*|\1"$(TAG)"|' $(VALUES) && rm -f $(VALUES).bak
	@echo "$(VALUES): image.tag -> $(TAG)"
