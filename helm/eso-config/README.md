# eso-config

A single `ClusterSecretStore` resource. It is the glue between External
Secrets Operator (the `external-secrets` chart) and Vault (the `vault` chart) —
without it, the `ExternalSecret` objects in `postgres-db` and `student-api` have
nothing to point at and stay permanently un-synced.

This chart intentionally does nothing else. Splitting it out from `vault` keeps
the store's lifecycle independent of Vault's — you can point it at a different
Vault, or re-run it after changing the auth role, without touching the Vault
StatefulSet.

## What this chart creates

| Resource | Name | Purpose |
| --- | --- | --- |
| ClusterSecretStore | `vault-backend` (fixed name, not release-prefixed) | Cluster-scoped store so an `ExternalSecret` in *any* namespace can use it |

The name is fixed rather than templated from the release name because every
consuming chart (`postgres-db`, `student-api`) hardcodes
`externalSecrets.secretStore: vault-backend` in its own `values.yaml`. If you
rename it here, update it in both of those charts too — there's no other link
between them.

## How it connects to the rest of the stack

```
external-secrets (operator)  ──┐
                                 │ ServiceAccount eso-ns/external-secrets
                                 ▼
                    ClusterSecretStore "vault-backend"  (this chart)
                                 │ Kubernetes auth, role "eso-role"
                                 ▼
                    vault.vault.svc.cluster.local:8200  (vault chart)
```

- **`clusterSecretStore.vault.server`** must resolve to the `vault` chart's
  Service — `http://<vault fullname>.<vault namespace>.svc.cluster.local:8200`.
- **`clusterSecretStore.vault.auth.kubernetes.role`** (`eso-role`) and the KV
  **`path`** (`secret`) must match what `make vault-configure` wrote into
  Vault. This chart only *declares* the auth method's mount path and role name
  — it does not create them in Vault; that's the Makefile's job because it
  needs a live, unsealed Vault to run `vault write auth/...` against.
- **`serviceAccountRef`** (`external-secrets` / `eso-ns`) must match the
  ServiceAccount the `external-secrets` chart creates for the operator. Vault
  validates this account's token via `TokenReview` (see the `vault` chart's
  RBAC) before honoring the login.

## Notable values

| Key | Default | Notes |
| --- | --- | --- |
| `clusterSecretStore.name` | `vault-backend` | Referenced by name in `postgres-db`/`student-api` — see above |
| `clusterSecretStore.vault.server` | `http://vault.vault.svc.cluster.local:8200` | Points at the `vault` chart's Service |
| `clusterSecretStore.vault.path` | `secret` | KV v2 mount path in Vault |
| `clusterSecretStore.vault.auth.kubernetes.role` | `eso-role` | Vault role bound in `make vault-configure` |

## Verifying

`READY` must be `True` — if it's not, Vault is sealed or the auth role isn't
configured yet:

```bash
kubectl get clustersecretstore vault-backend
kubectl describe clustersecretstore vault-backend
```

## Deploying

Requires the `external-secrets` operator's CRDs and an unsealed, configured
Vault:

```bash
helm upgrade --install eso-config ./helm/eso-config -n eso-ns --wait
```
