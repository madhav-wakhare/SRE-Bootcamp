# vault

HashiCorp Vault, deployed as a single-node StatefulSet with Raft storage. It is
the secret backend for the whole stack — no chart in this repository stores a
password or connection string directly; they all end up in Vault and flow out
through External Secrets Operator (ESO).

## What this chart creates

| Resource | Name | Purpose |
| --- | --- | --- |
| ServiceAccount | `vault` | Kubernetes identity for the Vault pod |
| ClusterRole / ClusterRoleBinding | `vault-vault-tokenreview` | Lets Vault call the `TokenReview` API — required for Vault's Kubernetes auth method, which ESO logs in with |
| ConfigMap | `vault-config` | Renders `vault.hcl` (listener, Raft storage path, `api_addr`/`cluster_addr`) |
| StatefulSet | `vault` | Runs `hashicorp/vault`, one replica, Raft storage. An initContainer (`fix-permissions`) chowns the data volume to `100:1000` before the main container starts, since fresh PVCs are owned by root |
| Service | `vault` | ClusterIP — the address every other component talks to |
| Service | `vault-headless` | Headless, governs the StatefulSet, gives the pod a stable DNS name for its own `VAULT_CLUSTER_ADDR` |

## How it connects to the rest of the stack

```
                       ┌────────────────────┐
                       │  vault (this chart) │
                       │  vault.vault.svc:8200│
                       └─────────┬────────────┘
                                 │ read secret/one2n/dev/app-config
                                 │ (Kubernetes auth, role "eso-role")
                       ┌─────────┴────────────┐
                       │      eso-config       │  ClusterSecretStore "vault-backend"
                       └─────────┬────────────┘
                    ┌────────────┴────────────┐
           ExternalSecret               ExternalSecret
           (postgres-db chart)          (student-api chart)
```

- **`eso-config`** points its `ClusterSecretStore` at
  `http://vault.vault.svc.cluster.local:8200` (this chart's Service). If you
  install this chart under a different release name or namespace, update
  `clusterSecretStore.vault.server` in the `eso-config` chart's values.
- **`external-secrets`** (the ESO operator) is the client that actually calls
  Vault. It authenticates as the `external-secrets` ServiceAccount in `eso-ns`,
  which must be bound to the `eso-role` Vault role — done by `make
  vault-configure`, not by this chart. Vault ships sealed and empty; it has no
  opinion about ESO until that command runs.
- **`postgres-db`** and **`student-api`** never talk to Vault directly. They only
  read the Kubernetes Secrets that ESO writes.

## Notable values

| Key | Default | Notes |
| --- | --- | --- |
| `image.tag` | `""` | Falls back to `.Chart.AppVersion` (`2.0.3`) |
| `nodeSelector` | `{type: dependent_services}` | Matches the bootcamp's multi-node minikube labels; set to `null` on a single-node cluster |
| `persistence.storageClass` | `standard` | minikube's default StorageClass |
| `persistence.size` | `1Gi` | Retained on `helm uninstall` — reused across reinstalls unless you delete the PVC |
| `ports.api` / `ports.cluster` | `8200` / `8201` | Vault's listener and Raft cluster ports |

## Operating it

This chart only gets Vault *running* — sealed, uninitialized, with no secret
engine or auth method. Everything else is a `make` target, because it requires
talking to the running pod, not just applying manifests:

```bash
helm upgrade --install vault ./helm/vault -n vault --create-namespace --wait
make vault-init        # one-time: writes hashicorp-vault/vault-keys.json (gitignored)
make vault-unseal       # required after every restart — Vault always boots sealed
make vault-configure    # enables KV v2 + the Kubernetes auth role ESO logs in with
make vault-seed         # writes db_password / db_url under secret/one2n/dev/app-config
```

Check status directly:

```bash
kubectl exec -n vault vault-0 -c vault -- vault status
```

`hashicorp-vault/vault-keys.json` holds the unseal key and root token. It is
gitignored on purpose — losing it makes the existing Vault data unrecoverable,
at which point `make helm-vault-reset` wipes and rebuilds from scratch.
