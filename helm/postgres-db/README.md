# postgres-db

PostgreSQL for the Student API, run as a single-replica StatefulSet. The chart
never stores `POSTGRES_PASSWORD` itself — it is synced in from Vault by an
`ExternalSecret`, so neither the chart nor its `values.yaml` holds any secret.

Install it with the release name `postgres-db`; every resource is named after
the release, and the DNS name that name produces is baked into the `db_url`
stored in Vault.

## What this chart creates

| Template | Resource | Purpose |
| --- | --- | --- |
| `configmap.yaml` | ConfigMap `postgres-db-config` | Non-secret settings: `POSTGRES_USER`, `POSTGRES_DB` |
| `externalsecret.yaml` | ExternalSecret `postgres-db` | Tells ESO to copy `db_password` from Vault into Secret `postgres-db-secret` as `POSTGRES_PASSWORD` |
| `statefulset.yaml` | StatefulSet `postgres-db` | `postgres:17-alpine`, one replica, `pg_isready` probes, PVC `data-postgres-db-0` (1Gi, kept on uninstall) |
| `service.yaml` | Service `postgres-db` | Headless — one stable DNS name for the single pod |

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

- **`externalSecret.secretStore`** (`vault-backend`) must match the
  `ClusterSecretStore` name created by the `eso-config` chart.
- **`externalSecret.remoteKey` / `remoteProperty`** (`one2n/dev/app-config` /
  `db_password`) must match what `make vault-seed` wrote into Vault.
- This chart does **not** know about `student-api`. The link is entirely inside
  Vault: the seeded `db_url` hardcodes this chart's Service DNS name,
  `postgres-db.<namespace>.svc.cluster.local:5432`. **Rename this release or its
  namespace and the API's `DATABASE_URL` breaks until you re-run
  `make vault-seed`.**

## Notable values

| Key | Default | Notes |
| --- | --- | --- |
| `config.POSTGRES_USER` / `config.POSTGRES_DB` | `postgres` / `students_db` | Must match the values baked into `db_url` in Vault |
| `nodeSelector` | `{type: database}` | Matches the bootcamp's multi-node minikube labels |
| `persistence.size` | `1Gi` | Increase before the volume fills, not after — resizing needs a StorageClass that supports expansion |
| `externalSecret.secretStore` | `vault-backend` | Must match `eso-config`'s `name` |

## Deploying

Requires the `eso-config` `ClusterSecretStore` to be `READY`, which in turn needs
an unsealed, configured, and seeded Vault:

```bash
helm upgrade --install postgres-db ./helm/postgres-db -n student-api --create-namespace --wait
```

If the pod sits in `CreateContainerConfigError`, the ESO Secret does not exist
yet — check `kubectl get externalsecret postgres-db -n student-api`.
