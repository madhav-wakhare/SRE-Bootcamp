# Student CRUD REST API

This repository contains a simple Flask-based REST API for managing students. It exposes endpoints for creating, listing, retrieving, updating, and deleting student records.

## Features
- CRUD operations for students
- Versioned API routes under `/api/v1/students`
- Health check endpoint at `/healthcheck`
- PostgreSQL database with SQLAlchemy (SQLite fallback for unit testing)
- Environment-based database configuration
- Unit tests for the main API flows

## Beginner-friendly concepts used
- Flask: a small Python web framework for building web apps.
- Route: a URL that your app responds to, such as `/api/v1/students`.
- HTTP methods: `GET` reads data, `POST` creates data, `PUT` updates data, and `DELETE` removes data.
- JSON: a common format for sending data between a client and a server.
- SQLAlchemy: a Python library that helps you work with databases using Python objects.
- Environment variables: values passed into the app from the shell, such as `DATABASE_URL`.
- pytest: a Python testing tool used to verify your app works correctly.

## Prerequisites & Installation

To run this application locally, you need `docker` (with docker compose) and `make` installed.

If you do not have these tools installed, you can use the following helper functions to install them based on your OS:

### macOS (using Homebrew)
```bash
# Function to install prerequisites on macOS
install_macos_prereqs() {
  echo "Installing Homebrew if not present..."
  command -v brew >/dev/null 2>&1 || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  
  echo "Installing Make..."
  xcode-select --install || true
  
  echo "Installing Docker..."
  brew install --cask docker
  
  echo "Prerequisites installation complete. Please ensure Docker is running."
}
```

### Linux (Ubuntu/Debian)
```bash
# Function to install prerequisites on Ubuntu/Debian
install_linux_prereqs() {
  echo "Updating package lists..."
  sudo apt-get update
  
  echo "Installing Make and build tools..."
  sudo apt-get install -y build-essential
  
  echo "Installing Docker..."
  sudo apt-get install -y docker.io docker-compose-v2
  
  echo "Adding user to docker group..."
  sudo usermod -aG docker $USER
  
  echo "Prerequisites installation complete. Please log out and log back in."
}
```

---

## One-Click Local Development Setup

We support a simplified, containerized one-click local development setup using Docker Compose and `make`.

### Docker Network Setup
Ensure that the external network `sre-network` exists before running the compose stack:
```bash
docker network create sre-network
```

### Make Targets and Order of Execution
The Makefile contains targets to build, migrate, and run the services. 

1. **Start the Database Container**:
   Starts the PostgreSQL container in the background.
   ```bash
   make db-start
   ```

2. **Run DB Migrations inside Docker**:
   Applies DML schema migrations inside the container.
   ```bash
   make migrate-server
   ```

3. **Build the REST API Docker Image**:
   Builds the Docker image for the Flask application.
   ```bash
   make docker-build
   ```

4. **One-Click Run (REST API & DB)**:
   You have two choices depending on where you want the REST API application to run:

   - **Option A: Run REST API inside Docker Compose**:
     Starts/verifies the database container, checks/applies migrations in the container, and starts the REST API service inside Docker Compose.
     ```bash
     make docker-run
     ```

   - **Option B: Run REST API locally (on Host)**:
     Starts/verifies the database container, checks/applies migrations locally, and starts the REST API service locally on your host machine.
     ```bash
     make run-server
     ```


---

## Manual Local Setup (Without Docker)

1. Create and activate a virtual environment:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```
2. Install dependencies:
   ```bash
   make install
   ```
3. Configure environment variables. Create a `.env` file at the root of the project:
   ```env
   DATABASE_URL=postgresql://postgres:postgres@localhost:5432/students_db
   PORT=5000
   ```
   *(The application automatically loads variables from `.env` at startup using `python-dotenv`.)*
4. Run database migrations/schema setup locally:
   ```bash
   make migrate
   ```
5. Start the application locally:
   ```bash
   make run
   ```


## Testing
```bash
make test
```

## API endpoints
- `GET /healthcheck`
- `POST /api/v1/students`
- `GET /api/v1/students`
- `GET /api/v1/students/<id>`
- `PUT /api/v1/students/<id>`
- `DELETE /api/v1/students/<id>`

---

## Continuous Integration (CI) Pipeline

A GitHub Actions workflow is defined in `.github/workflows/ci.yml` that automates build, test, lint, and packaging tasks on a **self-hosted runner**.

### Pipeline Stages
1. **Build API**: Runs `make install` to install dependencies in the repository workspace.
2. **Perform Code Linting**: Runs `make lint` (Hadolint check for the `Dockerfile`).
3. **Run Tests**: Runs `make test` (pytest unit test suite).
4. **Docker Login**: Logs into Docker Hub using secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.
5. **Docker Build and Push**: Builds the Docker image (using `make docker-build`) and pushes it to Docker Hub (`<dockerhub-username>/sre-student-api:<7-char-commit-hash>`).


### Triggers
* **Automatic**: Triggers on pushes or pull requests affecting production code/configuration files (`app.py`, `migrations/`, `tests/`, `requirements.txt`, `Dockerfile`, `Makefile`).
* **Manual**: Allows manual workflow runs from the GitHub Actions tab (`workflow_dispatch`).


### Setting Up a Self-Hosted Runner
To execute the pipeline, configure a self-hosted runner on your local machine:
1. Navigate to your GitHub repository -> **Settings** -> **Actions** -> **Runners** -> **New self-hosted runner**.
2. Select your OS (macOS/Linux) and architecture.
3. Follow the provided commands to download, configure, and launch the runner:
   ```bash
   # Example Configuration (Replace with token from GitHub Settings)
   ./config.sh --url https://github.com/<owner>/<repo> --token <registration-token>
   
   # Run the worker
   ./run.sh
   ```

---

## Kubernetes Cluster Setup (Minikube)

The cluster this stack runs on is a local, multi-node Minikube cluster that
stands in for a "production" cluster. It has **four nodes**: a dedicated
control-plane that runs no application workload, and three worker nodes — one
per responsibility.

| Node | Role | Label |
| --- | --- | --- |
| `minikube` (control-plane) | Cluster control-plane only — cordoned, no workloads scheduled here | *(none)* |
| `minikube-m04` | Application (the REST API) | `type=application` |
| `minikube-m02` | Database (PostgreSQL) | `type=database` |
| `minikube-m03` | Dependent services (Vault, and later observability) | `type=dependent_services` |

Every chart's `nodeSelector` (see [helm/vault/values.yaml](helm/vault/values.yaml),
[helm/postgres-db/values.yaml](helm/postgres-db/values.yaml),
[helm/student-api/values.yaml](helm/student-api/values.yaml)) targets one of
these `type` labels, which is what actually pins each component to its node.

### Bring up the cluster

```bash
make k8s-cluster-up
```

This starts a 4-node Minikube profile (Docker driver, 2 CPUs / 3Gi memory per
node) and applies the labels above. It is safe to re-run: Minikube only
provisions nodes on a profile's first start, and the labeling
(`kubectl cordon` / `kubectl label --overwrite`) is idempotent.

If you only need to reapply labels — e.g. after a node was recreated — without
touching the cluster's lifecycle:

```bash
make k8s-cluster-label
```

### Verify

```bash
make k8s-cluster-status
```

Expect all four nodes `Ready`, the control-plane showing the
`node.kubernetes.io/unschedulable` taint, and each worker showing its `type`
label.

### Tear down

```bash
make k8s-cluster-down
```

This deletes the entire cluster and everything deployed on it — every
namespace, every Helm release, every PVC. It is not a dependency of any other
target and must be run explicitly.

---

## Kubernetes Deployment with Helm

The stack runs on Kubernetes and is deployed **entirely with Helm charts**. Every
component lives in its own chart under [`helm/`](helm/), so each one can be
upgraded, rolled back, and versioned independently.

The raw manifests in `k8s/` and `hashicorp-vault/` are kept only as a historical
reference for the previous milestone. They are no longer the deployment path and
must not be applied alongside the Helm releases.

### Chart layout

```
helm/
├── external-secrets/     # Wrapper around the community External Secrets Operator chart
│   ├── Chart.yaml        #   declares the upstream chart as a dependency
│   ├── charts/           #   upstream chart vendored here, so no repo add is needed
│   └── values.yaml       #   values forwarded to the subchart
├── vault/                # HashiCorp Vault: StatefulSet, ConfigMap, Services, ServiceAccount, TokenReview RBAC
├── eso-config/           # ClusterSecretStore wiring ESO to Vault over Kubernetes auth
├── postgres-db/          # PostgreSQL StatefulSet, headless Service, ConfigMap, ExternalSecret
└── student-api/          # REST API Deployment (Alembic initContainer), NodePort Service, ConfigMap, ExternalSecret
```

Each chart follows the same conventions:

| Convention | Why |
| --- | --- |
| Resource names come from a `fullname` helper | Two releases of the same chart never collide |
| `app.kubernetes.io/*` labels on every object, selectors kept to the immutable subset | Standard labels, and selectors that stay patchable |
| No `metadata.namespace` in any template | The namespace comes from `helm --namespace`, keeping charts reusable |
| Image tag defaults to `.Chart.AppVersion` | Chart version and image version cannot drift apart |
| `checksum/config` pod annotation | A ConfigMap change actually rolls the pods |
| No secret value anywhere in a chart or in `values.yaml` | Secrets live in Vault and arrive via ESO |

### Component and release map

| Chart | Release | Namespace | Creates |
| --- | --- | --- | --- |
| `external-secrets` | `external-secrets` | `eso-ns` | ESO operator, webhook, cert-controller, CRDs |
| `vault` | `vault` | `vault` | `vault-0`, Services `vault` / `vault-headless` |
| `eso-config` | `eso-config` | `eso-ns` | ClusterSecretStore `vault-backend` (cluster scoped) |
| `postgres-db` | `postgres-db` | `student-api` | StatefulSet + Service `postgres-db`, Secret `postgres-db-secret` |
| `student-api` | `student-api` | `student-api` | Deployment + NodePort Service `student-api`, Secret `student-api-db-url` |

Release names intentionally match the chart names, which keeps the generated
resource names short and predictable. The DNS name
`postgres-db.student-api.svc.cluster.local` is embedded in the `db_url` stored in
Vault, so renaming the `postgres-db` release means re-running `make vault-seed`.

### How secrets flow

No password is stored in a chart, in `values.yaml`, or in git:

```
Vault (secret/one2n/dev/app-config)
  │   db_password, db_url
  │
  ├─ ClusterSecretStore "vault-backend"   (eso-config chart; ESO logs in to Vault
  │                                        as eso-ns/external-secrets over the
  │                                        Kubernetes auth method)
  │
  ├─ ExternalSecret postgres-db      → Secret postgres-db-secret     → POSTGRES_PASSWORD
  └─ ExternalSecret student-api-db-url → Secret student-api-db-url   → DATABASE_URL
```

### Prerequisites

* A running cluster. The charts' `nodeSelector`s target the bootcamp's multi-node
  minikube setup: `type=application`, `type=database`, `type=dependent_services`.
  Drop them with `--set nodeSelector=null` on a single-node cluster.
* `helm` 3.8+ and `kubectl` on your PATH, pointing at that cluster.

### First-time deployment

If the previous milestone's `kubectl apply` stack is still running, remove it
first. Helm will not adopt resources it did not create, and the old Service holds
the NodePort this chart wants:

```bash
make k8s-manifest-teardown     # deletes the student-api and vault-ns namespaces
make helm-legacy-cleanup       # removes releases from earlier iterations of these charts
```

Then deploy everything with one command:

```bash
make helm-install-all
```

That runs, in order:

1. `helm-install-eso-operator` — the operator and its CRDs.
2. `helm-install-vault` — Vault, which starts up sealed and empty.
3. `vault-setup` — `vault-init`, `vault-unseal`, `vault-configure`, `vault-seed`.
4. `helm-install-eso-config` — the ClusterSecretStore.
5. `helm-install-postgres` — PostgreSQL, whose password ESO now supplies.
6. `helm-install-student-api` — the REST API, migrations first.

Every step is idempotent, so the target is safe to re-run.

`make vault-init` writes the unseal key and root token to
`hashicorp-vault/vault-keys.json`. That file is gitignored — **never commit it**,
and if you lose it the Vault data becomes unrecoverable
(`make helm-vault-reset` then wipes and rebuilds Vault).

### Verifying

```bash
make helm-verify
```

This prints the releases, the ClusterSecretStore (`READY` must be `True`), the
ExternalSecrets (`STATUS` must be `SecretSynced`), the pods, and finally calls
`/healthcheck` through a temporary `kubectl port-forward` tunnel (cleaned up
automatically). The NodePort itself is not curled directly — on the Minikube
`docker` driver on macOS, `<node-ip>:30080` is never reachable from the host:
Docker Desktop only host-publishes a fixed port set per node container (see
`docker ps`), and the NodePort isn't one of them. Manually:

```bash
kubectl port-forward -n student-api svc/student-api 5000:5000
curl http://localhost:5000/healthcheck
curl http://localhost:5000/api/v1/students
```

On Linux, or with the `minikube` driver instead of `docker`, the node network
usually is directly routable and `curl http://$(minikube ip):30080/healthcheck`
works too — but don't rely on it on macOS.

### Day-to-day operations

| Command | What it does |
| --- | --- |
| `make helm-lint` | Lints all five charts |
| `make helm-template` | Renders every chart and validates it server-side without applying |
| `make helm-package` | Packages the charts as versioned `.tgz` files into `dist/` |
| `make helm-status` | Lists all releases |
| `make vault-unseal` | Unseals Vault, needed after every Vault pod restart |
| `make vault-seed` | Rewrites the secrets in Vault, e.g. `make vault-seed DB_PASSWORD=$(openssl rand -hex 16)` |
| `make helm-uninstall-all` | Uninstalls all releases, keeping the PVCs |
| `make helm-vault-reset` | Wipes Vault's storage and re-bootstraps it |

Deploying a new application image:

```bash
helm upgrade --install student-api ./helm/student-api -n student-api \
  --set image.tag=<commit-sha> --wait
```

Rolling back:

```bash
helm history student-api -n student-api
helm rollback student-api <revision> -n student-api
```

### Installing a single chart directly

The Makefile only wraps `helm upgrade --install`, so any chart can be installed
on its own:

```bash
helm upgrade --install external-secrets ./helm/external-secrets -n eso-ns --create-namespace --wait
helm upgrade --install vault            ./helm/vault            -n vault   --create-namespace --wait
helm upgrade --install eso-config       ./helm/eso-config       -n eso-ns  --wait
helm upgrade --install postgres-db      ./helm/postgres-db      -n student-api --create-namespace --wait
helm upgrade --install student-api      ./helm/student-api      -n student-api --wait
```

### Notable values

| Chart | Key | Default | Notes |
| --- | --- | --- | --- |
| `student-api` | `image.tag` | `""` | Empty falls back to `appVersion` (`bd10dca`) |
| `student-api` | `service.nodePort` | `30080` | Fixed so the URL survives reinstalls |
| `student-api` | `imagePullSecret.enabled` | `false` | The image is public; enable to have ESO build a `dockerconfigjson` Secret from Vault for a private registry |
| `student-api` | `migrations.enabled` | `true` | Runs `alembic upgrade head` as an initContainer |
| `postgres-db` | `persistence.size` | `1Gi` | PVC is retained on `helm uninstall` |
| `postgres-db` / `student-api` | `externalSecrets.secretStore` | `vault-backend` | Must match `clusterSecretStore.name` in `eso-config` |
| `eso-config` | `clusterSecretStore.vault.server` | `http://vault.vault.svc.cluster.local:8200` | Change if Vault's release or namespace changes |
| `vault` | `persistence.storageClass` | `standard` | minikube's default StorageClass |

### Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| ClusterSecretStore `READY=False` | Vault sealed, or Kubernetes auth not configured | `make vault-unseal`, `make vault-configure` |
| ExternalSecret not `SecretSynced` | KV path or property missing in Vault | `make vault-seed`, then `kubectl describe externalsecret -n student-api` |
| Pod in `CreateContainerConfigError` | The ESO Secret does not exist yet | Fix the ExternalSecret above; the pod recovers on its own |
| API pod stuck in `Init` | The migration container cannot reach Postgres | `kubectl logs -n student-api deploy/student-api -c run-migrations` |
| `helm install` reports invalid ownership metadata | Manifest-created resources still present | `make k8s-manifest-teardown` |
| `helm install` reports a name or NodePort already in use | A release from an earlier chart iteration is still installed | `make helm-legacy-cleanup` |
| Vault sealed after a node restart | Expected: Vault always restarts sealed | `make vault-unseal` |

---

## Further Reading
- [Helm Documentation](https://helm.sh/docs/)
- [Helm Chart Best Practices](https://helm.sh/docs/chart_best_practices/)
- [External Secrets Operator](https://external-secrets.io/)
- [HashiCorp Vault Kubernetes auth](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
