# argocd

A thin wrapper around the community [Argo CD](https://argo-cd.readthedocs.io/)
chart. The upstream chart is declared as a dependency and **vendored** into
`charts/argo-cd-10.2.2.tgz`, so `helm install` never needs to reach
`argoproj.github.io/argo-helm` at deploy time — only when you deliberately
re-run `helm dependency build` after bumping the version.

This chart installs the GitOps controller itself. It is the one component of
the stack that Argo CD does **not** manage: something has to deploy the
deployer. What Argo CD then deploys is described by the plain YAML manifests
in [`argocd-apps/`](../../argocd-apps/) at the repository root.

## What this chart creates

Everything the upstream `argo-cd` chart creates, under the `argocd` namespace by
convention:

| Resource | Purpose |
| --- | --- |
| StatefulSet `argocd-application-controller` | Reconciles every Application against git |
| Deployment `argocd-repo-server` | Clones this repository and runs `helm template` on the charts |
| Deployment `argocd-server` | API and web UI |
| Deployment `argocd-redis` | Cache shared by the components above |
| Deployment `argocd-applicationset-controller` | Unused here — chart 10.2.2 has no toggle to disable it |
| CRDs | `Application`, `AppProject`, `ApplicationSet` |
| Secret `argocd-initial-admin-secret` | Generated admin password (`make argocd-password`) |

Dex (SSO) and the notifications controller are disabled — neither is used, and
each is another pod on an already busy node.

## Values worth knowing

| Key | Default | Why it is set |
| --- | --- | --- |
| `argo-cd.global.nodeSelector.type` | `dependent_services` | Pins **every** Argo CD component to the dependent services node, as the milestone requires. The upstream chart fans this global selector out to all its workloads |
| `argo-cd.configs.params.controller.diff.server.side` | `true` | Diff via a server-side dry-run apply. Without it, fields the API server defaults (`deletionPolicy` on an ExternalSecret, `volumeMode` inside a StatefulSet's `volumeClaimTemplates`, …) read as drift and the `vault`, `postgres-db` and `student-api` Applications sit permanently `OutOfSync` — even immediately after a successful sync |
| `argo-cd.configs.cm.application.resourceTrackingMethod` | `annotation` | Tracks resources by the `argocd.argoproj.io/tracking-id` annotation. The charts in this repo set `app.kubernetes.io/instance` themselves, so the default label-based tracking would have Argo CD claim resources by coincidence of naming |
| `argo-cd.configs.cm.timeout.reconciliation` | `60s` | Git poll interval (upstream default is 3m). Keeps the commit → deployed loop short enough to watch |
| `argo-cd.configs.params.server.insecure` | `true` | The UI is reached over `kubectl port-forward`, where an in-pod TLS redirect would loop |
| `argo-cd.crds.keep` | `true` | `helm uninstall` of Argo CD does not take every Application object down with it |

Anything not overridden in `values.yaml` falls back to the
[upstream chart's defaults](https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/values.yaml).

## Deploying

```bash
make argocd-install
# equivalent to:
helm upgrade --install argocd ./helm/argocd -n argocd --create-namespace --wait
```

Then open the UI:

```bash
make argocd-password   # user: admin
make argocd-ui         # http://localhost:8090
```

## Maintaining the vendored dependency

```bash
# after bumping the version pin in Chart.yaml
helm dependency build ./helm/argocd
```

This re-downloads the pinned chart version into `charts/` and updates
`Chart.lock`. Commit both — the `.tgz` under `charts/` is intentionally **not**
gitignored, exactly like the vendored External Secrets Operator chart.
