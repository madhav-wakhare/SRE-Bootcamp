# postgres-db

PostgreSQL for the Student API, run as a single-replica StatefulSet. The chart
never stores `POSTGRES_PASSWORD` itself — it is synced in from Vault by an
`ExternalSecret`, so the chart and its `values.yaml` hold no secret material.

## What this chart creates

| Resource | Name | Purpose |
| --- | --- | --- |
| ConfigMap | `postgres-db-config` | Non-sensitive settings: `POSTGRES_USER`, `POSTGRES_DB` |
| ExternalSecret | `postgres-db` | Pulls `db_password` from Vault, writes it into a Secret as `POSTGRES_PASSWORD` |
| StatefulSet | `postgres-db` | Runs `postgres:17-alpine`, one replica, with a `pg_isready` readiness/liveness probe |
| Service | `postgres-db` | Headless — gives the pod a stable DNS name, no load balancing needed for a single writer |
| PersistentVolumeClaim (via `volumeClaimTemplates`) | `data-postgres-db-0` | 1Gi by default, retained on `helm uninstall` |

## How it connects to the rest of the stack

```
   eso-config: ClusterSecretStore "vault-backend"
                      │
                      ▼
   ExternalSecret "postgres-db"  ──►  Secret "postgres-db-secret" (POSTGRES_PASSWORD)
                      │
                      ▼
   StatefulSet "postgres-db"  ──►  Service "postgres-db" (headless, :5432)
                                          │
                                          ▼
                     read by student-api's DATABASE_URL (from Vault's db_url)
```

- **`externalSecrets.secretStore`** (`vault-backend`) must match the
  `ClusterSecretStore` name created by the `eso-config` chart.
- **`externalSecrets.remoteKey` / `remoteProperty`** (`one2n/dev/app-config` /
  `db_password`) must match what `make vault-seed` wrote into Vault.
- This chart does **not** know about `student-api`. The link between them is
  entirely inside Vault: the `db_url` secret seeded by `make vault-seed`
  hardcodes this chart's Service DNS name —
  `postgres-db.<namespace>.svc.cluster.local:5432`. **If you rename this
  release or its namespace, the API's `DATABASE_URL` breaks until you rerun
  `make vault-seed`.**
- If ESO is not available (`externalSecrets.enabled: false`), point
  `existingSecret.name`/`existingSecret.key` at a Secret you manage yourself —
  the StatefulSet reads whichever one `postgres-db.secretName` resolves to.

## Notable values

| Key | Default | Notes |
| --- | --- | --- |
| `config.POSTGRES_USER` / `config.POSTGRES_DB` | `postgres` / `students_db` | Must match the values baked into `db_url` in Vault |
| `nodeSelector` | `{type: database}` | Matches the bootcamp's multi-node minikube labels |
| `persistence.size` | `1Gi` | Increase before the volume fills, not after — resizing needs a StorageClass that supports expansion |
| `externalSecrets.secretStore` | `vault-backend` | Must match `eso-config`'s `clusterSecretStore.name` |

## Deploying

Requires the `eso-config` `ClusterSecretStore` to be `READY`, which in turn
needs an unsealed, configured, and seeded Vault:

```bash
helm upgrade --install postgres-db ./helm/postgres-db -n student-api --create-namespace --wait
```

If the pod sits in `CreateContainerConfigError`, the ESO Secret doesn't exist
yet — check `kubectl get externalsecret postgres-db -n student-api`.
