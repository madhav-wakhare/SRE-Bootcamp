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

## Why two Services (and `postgres-db` only has one)

These two Services serve different audiences, not the same one twice:

| Service | Type | Used by | Why |
| --- | --- | --- | --- |
| `vault` | ClusterIP | External clients — ESO, via `eso-config`'s `vault.server` | A stable virtual IP that kube-proxy load-balances to a **ready** pod only |
| `vault-headless` | headless (`clusterIP: None`) | The StatefulSet itself, and Vault pods talking to each other | Required by Kubernetes for a StatefulSet's `serviceName` — gives each pod its own resolvable DNS name |

The headless Service isn't optional: `statefulset.yaml`'s `serviceName` field points at it, and Kubernetes requires every StatefulSet to be governed by one. That's what makes `vault-0.vault-headless.vault.svc.cluster.local` resolvable — the address used for `VAULT_CLUSTER_ADDR`, i.e. how Vault nodes would reach each other over Raft if this ever scaled beyond one replica.

The detail that matters even at `replicaCount: 1`: only `vault-headless` sets `publishNotReadyAddresses: true` (see `templates/service.yaml`). That's needed so a Vault pod still joining Raft — and therefore not yet passing its readiness probe — can still be found by its peers over DNS. But that's exactly the property you don't want for client traffic: if ESO were pointed at the headless address, it could get routed straight to a sealed, crashed, or still-starting pod. The plain `vault` ClusterIP Service has no such override, so it follows normal Kubernetes behavior — only ready pods appear in its Endpoints, and a sealed/crashed Vault gives ESO a clean "no endpoint" failure instead of a hang.

**`postgres-db` only has one Service** (headless, no ClusterIP) because it has neither of the two reasons above: it always runs a single replica with no peer-to-peer clustering protocol, so there's no second pod to discover and no load-balancing decision to make — one stable DNS name covers both jobs. Vault's Raft-based clustering is what earns it the second Service; if `postgres-db` ever grew real multi-node replication, it would likely need the same split.

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
  `vault.server` in the `eso-config` chart's values.
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
engine or auth method. None of what follows can be expressed as a Helm
template: it's live process state inside the already-running pod (whether
Vault is sealed, what auth methods it has enabled, what's in its KV store),
not a Kubernetes object `helm install` could create or update. So it's a
`make` target for each step, each one `kubectl exec`-ing into the pod:

```bash
helm upgrade --install vault ./helm/vault -n vault --create-namespace --wait
make vault-init        # one-time: writes hashicorp-vault/vault-keys.json (gitignored)
make vault-unseal       # required after every restart — Vault always boots sealed
make vault-configure    # enables KV v2 + the Kubernetes auth role ESO logs in with
make vault-seed         # writes db_password / db_url under secret/one2n/dev/app-config
```

What each one actually does, and why it must run in that order:

| Target | Command run inside the pod | Why it has to come at this point |
| --- | --- | --- |
| `vault-init` | `vault operator init -key-shares=1 -key-threshold=1 -format=json` | Turns a brand-new Vault from "empty, no crypto material" into "has a master key, but locked." Runs exactly once ever — the target checks `"initialized": true` first and skips if so, since re-running `init` on an already-initialized Vault would either fail or generate a *different* key that no longer matches what's on disk. `-key-shares=1 -key-threshold=1` keeps this to a single unseal key instead of splitting it Shamir-style across several holders, which is fine for a single-operator dev cluster but not how you'd run this in a real multi-person production setup. |
| `vault-unseal` | `vault operator unseal <unseal_key>` | Vault is initialized but still refuses every read/write until unsealed — this decrypts the master key **in memory only**, nothing is written to disk by this step. Checks `"sealed": false` first, so it's a no-op if already unsealed. Vault reseals itself on every pod restart (crash, node drain, `helm upgrade` recreating the pod), so this is the one step in the chain you'll re-run repeatedly, not just once. |
| `vault-configure` | `secrets enable kv`, `auth enable kubernetes`, `write auth/kubernetes/config`, `policy write eso-policy`, `write auth/kubernetes/role/eso-role` | Needs an **unsealed** Vault, since every one of these is a write. This is what makes the `eso-config` chart's `ClusterSecretStore` (`serviceAccountRef: {name: external-secrets, namespace: eso-ns}`) mean anything — before this runs, Vault has never heard of that ServiceAccount or the `eso-role` it's bound to. |
| `vault-seed` | `vault kv put secret/one2n/dev/app-config db_password=... db_url=...` | Needs the KV engine enabled by `vault-configure` first. Writes the actual payload that `postgres-db`'s and `student-api`'s `ExternalSecret`s pull. |

All four guard with `test -s $(VAULT_KEYS) || exit 1` (except `vault-init`, which is what *creates* that file) — none of them can do anything useful without the root token that only the keys file holds.

### How the keys file is structured and read back

`make vault-init` redirects Vault's own `-format=json` output straight into
`hashicorp-vault/vault-keys.json` — nothing here is hand-typed or copy-pasted.
Its shape (values illustrative, never commit real ones):

```json
{
  "unseal_keys_b64": ["<base64 unseal key share>"],
  "unseal_keys_hex": ["<same key, hex-encoded>"],
  "unseal_shares": 1,
  "unseal_threshold": 1,
  "recovery_keys_b64": [],
  "recovery_keys_hex": [],
  "root_token": "hvs.<root token>"
}
```

Only two fields are ever read back: `unseal_keys_b64[0]` and `root_token`.
Reading happens through one small helper defined once in the Makefile:

```makefile
VAULT_JSON = python3 -c "import json,sys; print(json.load(open('$(VAULT_KEYS)'))[sys.argv[1]] if sys.argv[1]=='root_token' else json.load(open('$(VAULT_KEYS)'))['unseal_keys_b64'][0])"
```

`vault-unseal` calls it as `$(VAULT_JSON) unseal_key`; `vault-configure` and
`vault-seed` call it as `$(VAULT_JSON) root_token`. Concretely, for
`vault-configure`: the shell runs that command substitution, which spawns
Python, which opens the file, parses the JSON, and prints just the token
string to stdout; the surrounding shell captures that into `VAULT_TOKEN` and
passes it as an environment variable into the `kubectl exec` session, where
the `vault` CLI inside the pod picks up `VAULT_TOKEN` automatically. The file
itself never gets copied anywhere — only the one value extracted from it, per
command, per invocation.

Check status directly:

```bash
kubectl exec -n vault vault-0 -c vault -- vault status
```

`hashicorp-vault/vault-keys.json` is gitignored on purpose — losing it makes
the existing Vault data permanently unrecoverable (there is no "reset the
unseal key" operation; it's derived from data encrypted with it), at which
point `make helm-vault-reset` wipes the PVC and rebuilds Vault from scratch.
