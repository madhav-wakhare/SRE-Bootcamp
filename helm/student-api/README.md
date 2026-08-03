# student-api

The Student CRUD REST API (Flask). Alembic migrations run to completion in an
initContainer before the app container starts, so the app is never live against
a stale schema. The chart holds no secret material — `DATABASE_URL` is synced in
from Vault by an `ExternalSecret`.

Install it with the release name `student-api`; every resource is named after
the release.

## What this chart creates

| Template | Resource | Purpose |
| --- | --- | --- |
| `configmap.yaml` | ConfigMap `student-api-config` | Non-secret settings (`PORT`, `LOG_FILE`), loaded into the pod with `envFrom` |
| `externalsecret.yaml` | ExternalSecret `student-api-db-url` | Tells ESO to copy `db_url` from Vault into a Secret as `DATABASE_URL` |
| `deployment.yaml` | Deployment `student-api` | initContainer `run-migrations` (Alembic), then the app container with `/healthcheck` probes |
| `service.yaml` | Service `student-api` | `NodePort` on `30080`, so the API is reachable outside the cluster |

Each template is a plain Kubernetes manifest with values substituted — there are
no named templates or helper functions to look up.

## How it connects to the rest of the stack

```
   eso-config: ClusterSecretStore "vault-backend"
                      │
                      ▼
   ExternalSecret "student-api-db-url" ──► Secret "student-api-db-url" (DATABASE_URL)
                      │
                      ▼
   Deployment "student-api"
       ├─ initContainer "run-migrations"  (alembic upgrade head, uses DATABASE_URL)
       └─ container "student-api"          (Flask app, uses DATABASE_URL)
                      │
                      ▼
   Service "student-api" (NodePort :30080) ──► outside the cluster
```

- **`externalSecret.secretStore`** (`vault-backend`) must match the
  `ClusterSecretStore` created by `eso-config`.
- **`externalSecret.remoteKey` / `remoteProperty`** (`one2n/dev/app-config` /
  `db_url`) must match what `make vault-seed` wrote.
- **This chart never references `postgres-db`.** The link between them lives in
  Vault: the seeded `db_url` is what points the app at
  `postgres-db.<namespace>.svc.cluster.local:5432`.

## Notable values

| Key | Default | Notes |
| --- | --- | --- |
| `image.tag` | `bd10dca` | **Written by CI** — the `update-image-tag` job rewrites this line and Argo CD deploys it |
| `service.nodePort` | `30080` | Fixed, so the URL survives reinstalls |
| `probes.path` | `/healthcheck` | Matches the Flask route in `src/app/routes.py` |
| `nodeSelector` | `{type: application}` | Matches the bootcamp's multi-node minikube labels |
| `migrationCommand` | `python src/migrations/apply_migrations.py` | What the initContainer runs |

## Deploying

Requires `postgres-db` to be up and the `eso-config` `ClusterSecretStore` to be
`READY`:

```bash
helm upgrade --install student-api ./helm/student-api -n student-api --create-namespace --wait
```

Once Argo CD is running, deploy by editing `image.tag` in `values.yaml` and
committing instead — a manual `helm upgrade` gets reverted by self-heal.

If the pod is stuck in `Init`, the migration container cannot reach the database
yet:

```bash
kubectl logs -n student-api deploy/student-api -c run-migrations
```
