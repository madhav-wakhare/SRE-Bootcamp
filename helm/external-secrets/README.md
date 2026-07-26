# external-secrets

A thin wrapper around the community [External Secrets Operator](https://external-secrets.io/)
chart. The upstream chart is declared as a dependency and **vendored** into
`charts/external-secrets-2.8.0.tgz`, so `helm install` never needs to reach
`charts.external-secrets.io` at deploy time — only when you deliberately
re-run `helm dependency build` after bumping the version.

This is the operator itself: the controller, webhook, and cert-controller
Deployments, their CRDs (`ExternalSecret`, `ClusterSecretStore`, ...), and the
ServiceAccount ESO uses to authenticate to Vault. It must be installed before
any other chart in this repo that creates an `ExternalSecret` or
`ClusterSecretStore`.

## What this chart creates

Everything the upstream `external-secrets` chart creates, under the
`eso-ns` namespace by convention:

| Resource | Purpose |
| --- | --- |
| Deployments `external-secrets`, `external-secrets-webhook`, `external-secrets-cert-controller` | The operator's three components |
| CRDs | `ExternalSecret`, `ClusterExternalSecret`, `SecretStore`, `ClusterSecretStore`, ... |
| ServiceAccount `external-secrets` | The identity ESO's controller runs as — this is the account Vault's Kubernetes auth method validates |

See `values.yaml` for the subset of upstream keys this wrapper pins; anything
not overridden here falls back to the
[upstream chart's defaults](https://github.com/external-secrets/external-secrets/blob/main/deploy/charts/external-secrets/values.yaml).

## How it connects to the rest of the stack

```
   external-secrets (this chart, operator + CRDs)
          │
          │ ServiceAccount eso-ns/external-secrets
          ▼
   eso-config: ClusterSecretStore "vault-backend"  ──►  vault chart
          │
          ▼
   postgres-db / student-api: ExternalSecret objects
```

- **`serviceAccount.name`** (`external-secrets`) must match the
  `serviceAccountRef` inside the `eso-config` chart's `ClusterSecretStore`, and
  the `bound_service_account_names` Vault role written by `make
  vault-configure`. Change any one of the three and the others break silently
  — ESO logs in as the wrong (or a nonexistent) identity and every
  `ExternalSecret` fails to sync.
- This chart has no direct relationship to Vault — it only provides the
  machinery (CRDs + controller) that `eso-config`, `postgres-db`, and
  `student-api` build on.

## Maintaining the vendored dependency

```bash
# after bumping the version pin in Chart.yaml
helm dependency build ./helm/external-secrets
```

This re-downloads the pinned chart version into `charts/` and updates
`Chart.lock`. Commit both — the `.tgz` under `charts/` is intentionally **not**
gitignored, unlike `dist/` (the output of `make helm-package`).

## Deploying

```bash
helm upgrade --install external-secrets ./helm/external-secrets -n eso-ns --create-namespace --wait
```
