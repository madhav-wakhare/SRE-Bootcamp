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

Job `ci`:
1. **Build API**: Runs `make install` to install dependencies in the repository workspace.
2. **Perform Code Linting**: Runs `make lint` (Hadolint check for the `Dockerfile`).
3. **Run Tests**: Runs `make test` (pytest unit test suite).
4. **Docker Login**: Logs into Docker Hub using secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.
5. **Docker Build and Push**: Builds the Docker image (using `make docker-build`) and pushes it to Docker Hub (`<dockerhub-username>/sre-student-api:<7-char-commit-hash>`), and exports that tag as the job output `image_tag`.

Job `update-image-tag` (the CD hand-off — see
[GitOps deployments with Argo CD](#gitops-deployments-with-argo-cd) below):

6. **Pull the latest Helm charts**: Checks out the pushed branch and rebases onto its current tip.
7. **Update the image tag**: Runs `make helm-set-image-tag TAG=<sha>`, a single anchored `sed` that rewrites `image.tag` in [helm/student-api/values.yaml](helm/student-api/values.yaml). It fails the job if that key ever disappears, instead of quietly matching nothing.
8. **Commit and push**: Commits that one-line change back to the same branch, skipping the commit when the tag is already current (`git diff --quiet`). Argo CD is watching the branch and does the actual deployment.

This job deploys nothing itself. It runs on the same self-hosted runner, and
skips silently when the tag is already current.


### Triggers
* **Automatic**: Triggers on pushes or pull requests affecting production code/configuration files (`src/`, `pyproject.toml`, `uv.lock`, `Dockerfile`, `Makefile`).
* **Manual**: Allows manual workflow runs from the GitHub Actions tab (`workflow_dispatch`).
* `update-image-tag` runs on `push` and `workflow_dispatch` only — a pull request build must not rewrite its base branch.
* The commit it makes touches `helm/**`, which is deliberately *not* in the path filters, so a deployment commit cannot retrigger the pipeline. The commit message also carries `[skip ci]`, and pushes made with `GITHUB_TOKEN` do not trigger workflows either.

### Required secrets and permissions

| Secret / permission | Needed for |
| --- | --- |
| `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` | Pushing the image |
| `permissions: contents: write` | Letting `GITHUB_TOKEN` push the tag commit — already set on the job |
| `GITOPS_TOKEN` *(optional)* | Only if branch protection rejects `GITHUB_TOKEN` pushes; the workflow falls back to it automatically |


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

> These charts are still the source of truth, but `helm upgrade` is no longer
> how they reach the cluster — Argo CD applies them from git. See
> [GitOps deployments with Argo CD](#gitops-deployments-with-argo-cd). The Helm
> targets below remain the way to lint, template, and bootstrap a cluster that
> has no Argo CD yet.

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
├── student-api/          # REST API Deployment (Alembic initContainer), NodePort Service, ConfigMap, ExternalSecret
├── argocd/               # Wrapper around the community Argo CD chart (vendored, like external-secrets)
└── argocd-apps/          # Declarative Argo CD config: AppProject, repo Secret, one Application per chart
```

Each chart follows the same conventions:

| Convention | Why |
| --- | --- |
| Resource names come from `.Release.Name` | One plain expression, no helper template to look up |
| `app.kubernetes.io/name` and `/instance` labels on every object, written inline | The standard labels, and the same two used as the selector |
| No `metadata.namespace` in any template | The namespace comes from `helm --namespace`, keeping charts reusable |
| Image tag is set explicitly in `values.yaml` | What is deployed is visible in git, which is what Argo CD reads |
| `checksum/config` pod annotation | A ConfigMap change actually rolls the pods |
| No secret value anywhere in a chart or in `values.yaml` | Secrets live in Vault and arrive via ESO |
| No `_helpers.tpl`, no named templates, one file per resource | Every template reads as the Kubernetes manifest it produces |

### Component and release map

| Chart | Release | Namespace | Creates |
| --- | --- | --- | --- |
| `external-secrets` | `external-secrets` | `eso-ns` | ESO operator, webhook, cert-controller, CRDs |
| `vault` | `vault` | `vault` | `vault-0`, Services `vault` / `vault-headless` |
| `eso-config` | `eso-config` | `eso-ns` | ClusterSecretStore `vault-backend` (cluster scoped) |
| `postgres-db` | `postgres-db` | `student-api` | StatefulSet + Service `postgres-db`, Secret `postgres-db-secret` |
| `student-api` | `student-api` | `student-api` | Deployment + NodePort Service `student-api`, Secret `student-api-db-url` |
| `argocd` | `argocd` | `argocd` | Argo CD controller, repo-server, server, redis, CRDs |
| `argocd-apps` | `argocd-apps` | `argocd` | AppProject `sre-bootcamp`, repository Secret, the Applications |

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

> **Once Argo CD is running, both of those commands are the wrong tool.** With
> `selfHeal` enabled, Argo CD reverts anything applied outside git — usually
> within seconds. Change `image.tag` in
> [helm/student-api/values.yaml](helm/student-api/values.yaml) and commit, or
> roll back with `argocd app rollback` / by reverting the commit. See the next
> section.

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
| `student-api` | `image.tag` | `bd10dca` | **Written by CI** — the `update-image-tag` job rewrites this line and Argo CD deploys it. An empty value falls back to `appVersion` |
| `student-api` | `service.nodePort` | `30080` | Fixed so the URL survives reinstalls |
| `student-api` | `migrationCommand` | `python src/migrations/apply_migrations.py` | Run by the initContainer before the app starts |
| `postgres-db` | `persistence.size` | `1Gi` | PVC is retained on `helm uninstall` |
| `postgres-db` / `student-api` | `externalSecret.secretStore` | `vault-backend` | Must match `name` in `eso-config` |
| `eso-config` | `vault.server` | `http://vault.vault.svc.cluster.local:8200` | Change if Vault's release or namespace changes |
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

## GitOps deployments with Argo CD

Everything above describes how the stack is *defined*. This section describes
how it now gets *deployed*: nobody runs `helm upgrade` any more. Argo CD watches
the Helm charts under [`helm/`](helm/) on the tracked branch and applies them
itself, so **git is the only place a change is made** and the cluster follows.

```
  git push (src/**)
        │
        ▼
  GitHub Actions, self-hosted runner
    job "ci"                lint -> test -> docker build -> docker push :<sha>
        │
        ▼
    job "update-image-tag"  git pull --rebase
                            make helm-set-image-tag TAG=<sha>  (rewrites helm/student-api/values.yaml)
                            git commit && git push             ← the deployment "request"
        │
        ▼
  Argo CD (in-cluster, polls every 60s)
    detects the new commit -> helm template helm/student-api -> apply -> rollout
```

The CI pipeline never touches the cluster and needs no kubeconfig: it only
writes a commit. Argo CD, running inside the cluster, does the rest.

### Components

| Chart | What it is |
| --- | --- |
| [`helm/argocd`](helm/argocd/) | Argo CD itself — a wrapper around the community chart, vendored into `charts/` exactly like the External Secrets Operator chart. The only component Argo CD does not manage; something has to deploy the deployer |
| [`helm/argocd-apps`](helm/argocd-apps/) | The declarative configuration: the `sre-bootcamp` AppProject, the repository Secret, one `Application` per chart, and the app-of-apps root |

Nothing is created with `argocd app create` or `argocd repo add`. Every Argo CD
object is a Kubernetes manifest rendered by a chart in this repository, so a
deployment change is reviewable in a pull request.

All Argo CD components run in the **`argocd`** namespace on the
**`dependent_services`** node — `argo-cd.global.nodeSelector` in
[helm/argocd/values.yaml](helm/argocd/values.yaml) pins every one of them:

```
$ kubectl get pods -n argocd -o wide
NAME                                               READY   STATUS      NODE
argocd-application-controller-0                    1/1     Running     minikube-m03
argocd-applicationset-controller-d95d77894-qld5s   1/1     Running     minikube-m03
argocd-redis-8697bb7967-ht48p                      1/1     Running     minikube-m03
argocd-repo-server-6ddcf9fb4b-lktq9                1/1     Running     minikube-m03
argocd-server-5d44ff4f7-75wg6                      1/1     Running     minikube-m03
```

### The Applications

Each `Application` points at a **chart path plus its `values.yaml`** — Argo CD
runs `helm template` on it, so the charts and their values are the source of
truth for what runs in the cluster.

| Application | Path | Namespace | Wave |
| --- | --- | --- | --- |
| `external-secrets` | `helm/external-secrets` | `eso-ns` | 0 |
| `vault` | `helm/vault` | `vault` | 1 |
| `eso-config` | `helm/eso-config` | `eso-ns` | 2 |
| `postgres-db` | `helm/postgres-db` | `student-api` | 3 |
| `student-api` | `helm/student-api` | `student-api` | 4 |
| `sre-bootcamp-root` | `helm/argocd-apps` | `argocd` | −1 |

`sre-bootcamp-root` is the app-of-apps: it points back at the `argocd-apps`
chart, so after the one bootstrap install the Applications themselves are
managed by git — add another `application-*.yaml` file under
[helm/argocd-apps/templates/](helm/argocd-apps/templates/), push, and Argo CD
creates the Application on its own.

All of them auto-sync with `prune` and `selfHeal` on.

### Setting Argo CD up

Prerequisite: a cluster (`make k8s-cluster-up`) and, for the very first
bootstrap of an empty cluster, nothing else — Argo CD creates the namespaces and
deploys the whole stack itself.

```bash
# 1. Install Argo CD (namespace argocd, dependent_services node)
make argocd-install

# 2. Point it at this repository. ARGOCD_REVISION is the branch it tracks.
#    Disable the root app on the very first run: helm/argocd-apps does not exist
#    on the tracked branch until this commit is pushed.
make argocd-apps-install ARGOCD_REVISION=main \
  ARGOCD_APPS_EXTRA='--set rootApp=false'

# 3. Once pushed, re-run with the root app enabled (the default)
make argocd-apps-install ARGOCD_REVISION=main
```

or both install steps at once with `make argocd-bootstrap`.

Vault is the one thing GitOps cannot finish: Argo CD deploys the StatefulSet,
but Vault always starts sealed. Run the one-time bootstrap after the `vault`
Application goes Healthy:

```bash
make vault-setup       # init, unseal, configure Kubernetes auth, seed secrets
make vault-unseal      # again after every Vault pod restart
```

Until Vault is unsealed the `eso-config` ClusterSecretStore reports `NotReady`
and the two ExternalSecrets do not sync — the Applications still show `Synced`,
because git and the cluster do agree; it is the pods that wait.

### Adopting a stack that Helm already deployed

If `make helm-install-all` has already run on this cluster, **nothing needs to
be torn down first**. Argo CD adopts the existing objects: the Applications use
`helm.releaseName`, so the rendered names are identical, and `ServerSideApply`
transfers field ownership from Helm without recreating anything. On this
cluster, adoption left every pod running with zero restarts.

The old Helm release secrets stay behind harmlessly. Stop using
`helm upgrade` on those releases from that point on — `selfHeal` will revert
whatever it does.

### Watching and operating it

| Command | What it does |
| --- | --- |
| `make argocd-status` | Argo CD pods (with their node) and the Applications |
| `make argocd-verify` | Sync/health per Application, plus the image tag in git vs the one running, plus the full `helm-verify` output |
| `make argocd-ui` | Port-forwards the UI to <http://localhost:8090> |
| `make argocd-password` | Prints the generated `admin` password |
| `make argocd-refresh` | Forces an immediate re-poll of git instead of waiting out the 60s interval |
| `make argocd-uninstall` | Removes Argo CD but **keeps** the stack running (strips the Application finalizers first) |

```bash
$ kubectl get applications -n argocd
NAME               SYNC STATUS   HEALTH STATUS
eso-config         Synced        Healthy
external-secrets   Synced        Healthy
postgres-db        Synced        Healthy
student-api        Synced        Healthy
vault              Synced        Healthy
```

The UI is reached through a port-forward for the same reason `make helm-verify`
tunnels to the API: on the Minikube docker driver on macOS a NodePort is never
routable from the host.

### Deploying a change end to end

1. Push a change under `src/**` to the tracked branch.
2. CI lints, tests, builds, and pushes `wakharemadhav/sre-student-api:<sha>`.
3. `update-image-tag` runs `make helm-set-image-tag` to rewrite `image.tag` in
   [helm/student-api/values.yaml](helm/student-api/values.yaml), and commits it.
4. Argo CD notices within ~60s (or immediately, with `make argocd-refresh`) and
   rolls out the new image.

To deploy by hand, make the same edit CI would and commit it:

```bash
make helm-set-image-tag TAG=$(git rev-parse --short=7 HEAD)
git commit -am "chore(deploy): student-api image tag -> $(git rev-parse --short=7 HEAD)"
git push
```

Rolling back is `git revert` of that commit — or, for a quick one, the UI's
**History and Rollback**. A rollback that is not in git gets reverted by
`selfHeal` at the next reconcile, which is the point of GitOps.

Verifying that git and the cluster agree:

```bash
make argocd-verify
```

### Design notes

A few settings exist for non-obvious reasons and are worth keeping:

| Setting | Why |
| --- | --- |
| `controller.diff.server.side: true` ([helm/argocd/values.yaml](helm/argocd/values.yaml)) | Diffs through a server-side dry-run apply. Without it, every field the API server defaults — `deletionPolicy` on an ExternalSecret, `volumeMode` inside a StatefulSet's `volumeClaimTemplates` — reads as drift, and `vault`, `postgres-db` and `student-api` sit permanently `OutOfSync` immediately after a successful sync |
| `application.resourceTrackingMethod: annotation` | The charts here set `app.kubernetes.io/instance` themselves; with the default label-based tracking Argo CD would claim resources by coincidence of naming |
| `ServerSideApply=true` on every Application | The ESO CRDs are too large for the annotation a client-side apply writes, and SSA is what makes adoption from Helm work |
| `ignoreDifferences` on the `external-secrets` app | ESO's cert-controller injects a CA bundle into its own webhooks and CRDs at runtime — a value that legitimately is not in git |
| `resources-finalizer` on every Application | Deleting an Application removes what it created instead of orphaning it. `make argocd-uninstall` strips it first, so removing Argo CD does not remove the stack |

### Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Application `Unknown` with `path does not exist` | The tracked branch does not have that chart yet | Push the branch, or install with `ARGOCD_REVISION=<your-branch>` |
| Application stays `OutOfSync` right after a successful sync | Server-side diff is off | Check `kubectl get cm argocd-cmd-params-cm -n argocd -o jsonpath='{.data.controller\.diff\.server\.side}'` is `true`, then restart the controller |
| `helm upgrade` of `argocd-apps` fails with a field-manager conflict | An Application was edited with `kubectl patch`, which took ownership of the field | Re-apply with `helm template ... \| kubectl apply --server-side --force-conflicts --field-manager=helm` once, then use Helm again |
| A manual `kubectl` change keeps reverting | Working as designed — `selfHeal` | Make the change in git |
| CI's tag commit is rejected | Branch protection blocks `GITHUB_TOKEN` | Add a `GITOPS_TOKEN` secret (a PAT with `contents: write`) |
| Applications `Synced` but pods stuck in `CreateContainerConfigError` | Vault sealed, so ESO has not created the Secrets | `make vault-unseal` |

---

