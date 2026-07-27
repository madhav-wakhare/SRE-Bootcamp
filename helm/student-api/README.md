# student-api

The Student CRUD REST API (Flask). Alembic migrations run to completion in an
initContainer before the app container starts, so the app is never live
against a stale schema. Like `postgres-db`, it holds no secret material itself
— `DATABASE_URL` is synced in from Vault by an `ExternalSecret`.

## What this chart creates

| Resource | Name | Purpose |
| --- | --- | --- |
| ConfigMap | `student-api-config` | Non-sensitive settings: `PORT`, `LOG_FILE` |
| ExternalSecret | `student-api-db-url` | Pulls `db_url` from Vault, writes it into a Secret as `DATABASE_URL` |
| ExternalSecret (optional) | `student-api-registry` | Only if `imagePullSecret.enabled: true` — builds a `dockerconfigjson` Secret from Vault, for a private image registry |
| Deployment | `student-api` | `initContainer` `run-migrations` runs `alembic upgrade head`, then the `student-api` container starts with `/healthcheck` readiness/liveness probes |
| Service | `student-api` | `NodePort` on `30080` by default, so it's reachable outside the cluster |

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

- **`externalSecrets.secretStore`** (`vault-backend`) must match the
  `ClusterSecretStore` created by `eso-config`.
- **`externalSecrets.remoteKey` / `databaseUrl.remoteProperty`**
  (`one2n/dev/app-config` / `db_url`) must match what `make vault-seed` wrote.
- **Depends on `postgres-db` only through the connection string in Vault** —
  this chart never references the `postgres-db` release or Service directly.
  The `db_url` value seeded by `make vault-seed` is what actually points the
  app at `postgres-db.<namespace>.svc.cluster.local:5432`.
- If ESO is not available (`externalSecrets.enabled: false`), point
  `existingSecret.name`/`existingSecret.key` at a Secret you manage yourself.
- `imagePullSecret.enabled` defaults to `false` because
  `wakharemadhav/sre-student-api` is a public image. Flip it on (and set
  `imagePullSecret.remoteProperty`) only if you push to a private registry and
  need Vault to hold the registry credentials.

## Notable values

| Key | Default | Notes |
| --- | --- | --- |
| `image.tag` | `""` | Falls back to `.Chart.AppVersion` (`bd10dca`) — bump both together on release |
| `service.nodePort` | `30080` | Fixed so the URL survives reinstalls |
| `migrations.enabled` | `true` | Set `false` only if migrations are applied some other way (e.g. a separate Job) |
| `probes.path` | `/healthcheck` | Matches the Flask route in `src/app/routes.py` |
| `nodeSelector` | `{type: application}` | Matches the bootcamp's multi-node minikube labels |

## Deploying

Requires `postgres-db` to be up and the `eso-config` `ClusterSecretStore` to be
`READY`:

```bash
helm upgrade --install student-api ./helm/student-api -n student-api --create-namespace --wait
```

Deploying a new image build:

```bash
helm upgrade --install student-api ./helm/student-api -n student-api --set image.tag=<commit-sha> --wait
```

If the pod is stuck in `Init`, the migration container can't reach the
database yet:

```bash
kubectl logs -n student-api deploy/student-api -c run-migrations
```
