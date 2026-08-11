# observability

The PLG (Promtail, Loki, Grafana) logging stack plus Prometheus metrics
monitoring for the Student REST API and its dependent services.

Eight upstream charts are declared as dependencies and **vendored** into
`charts/`, so `helm install` never needs to reach an external Helm repo at
deploy time — only when you deliberately re-run `helm dependency build` after
bumping a version. Every version is pinned exactly; none is a range.

## The one idea to hold onto

There are **two completely separate pipelines**. Prometheus and Loki never talk
to each other — they meet only inside Grafana.

```
METRICS  (Prometheus PULLS)                LOGS  (Loki RECEIVES pushes)

  node-exporter     ─┐                       pod writes to stdout
  kube-state-metrics ┤                              │
  postgres-exporter  ┼──► Prometheus         /var/log/pods on the node
  blackbox-exporter ─┘        │                     │
                              │              Promtail (DaemonSet) tails it
                              │                     │ pushes
                              │                   Loki
                              └──────────┬──────────┘
                                         ▼
                                      Grafana
```

|  | Prometheus | Loki |
| --- | --- | --- |
| Data | numbers | text lines |
| Direction | **pulls** from targets | **receives** pushes |
| Knows its sources? | yes, a target list | no, whoever POSTs |
| Query language | PromQL | LogQL |
| Indexes | everything | **labels only**, never log text |

Grafana stores neither. Every panel runs a live query, so deleting Grafana
loses no observability data.

## What this chart creates

Everything lands in the `observability-ns` namespace, on the node labelled
`type=dependent_services` — except the two DaemonSets, which must run
everywhere.

| Component | Kind | Service | Reads from |
| --- | --- | --- | --- |
| `prometheus-server` | Deployment | `prometheus-server:80` | scrapes the exporters below |
| `kube-state-metrics` | Deployment | `kube-state-metrics:8080` | the Kubernetes API — object state |
| `node-exporter` | **DaemonSet** | `node-exporter:9100` | `/proc`, `/sys` on each machine |
| `postgres-exporter` | Deployment | `postgres-exporter:80` | PostgreSQL in `student-api` |
| `blackbox-exporter` | Deployment | `blackbox-exporter:9115` | probes URLs it is told to |
| `loki` | StatefulSet | `loki:3100` | receives pushes from Promtail |
| `promtail` | **DaemonSet** | — | `/var/log/pods` on each machine |
| `grafana` | Deployment | `grafana:80` | queries Prometheus and Loki |

Plus two `ExternalSecret` objects (`postgres-exporter-db`, `grafana-admin`)
from this chart's own `templates/`.

### Why two of them are DaemonSets

`node-exporter` reads `/proc` and `/sys`, and `promtail` reads
`/var/log/pods` — both are **per-machine** files. There is no remote API for
another node's kernel or another node's disk, so a process has to be on that
node. Pinning either to `dependent_services` would blind you to every other
node, which is why their `nodeSelector` is deliberately empty.

Everything else is an ordinary workload and goes where the deployment diagram
says.

## The four exporters, and why each exists

An **exporter** is just a program that republishes something as text over
HTTP. That is the whole concept:

```
node_memory_MemAvailable_bytes 1.2345e+09
kube_pod_status_phase{pod="student-api-1",phase="Running"} 1
```

| Exporter | Answers |
| --- | --- |
| **node-exporter** | Is the machine healthy? CPU, memory, disk, network |
| **kube-state-metrics** | Is Kubernetes happy? replicas wanted vs ready, restarts, pod phases |
| **postgres-exporter** | Is the database healthy? connections, transactions, locks, replication |
| **blackbox-exporter** | Can I reach the endpoint, and how fast? |

They do not overlap. node-exporter cannot tell you a pod is CrashLooping;
kube-state-metrics cannot tell you the node is out of memory. And the
Kubernetes API stores no live CPU or memory usage at all — that exists only in
each machine's kernel, right now, which is why node-exporter has to be there.

### blackbox-exporter works differently

Every other exporter reports on itself. This one probes somebody else, and the
scrape job is shaped accordingly: **Prometheus does not scrape the endpoints,
it scrapes the exporter**, passing each endpoint as a `?target=` parameter.

```yaml
- source_labels: [__address__]      # 1. the listed URL becomes the query param
  target_label: __param_target
- source_labels: [__param_target]   # 2. label the metric with the endpoint...
  target_label: instance
- target_label: __address__         # 3. ...but send the request to the exporter
  replacement: blackbox-exporter.observability-ns.svc.cluster.local:9115
```

The endpoints probed are listed in `values.yaml` under the `blackbox-http` and
`blackbox-https` scrape jobs: the REST API's `/healthcheck`, Vault's
`/v1/sys/health`, and the Argo CD server's `/healthz`. Argo CD needs the
separate `http_2xx_insecure_tls` module because it presents its own
certificate.

## How secrets flow

Two credentials come out of Vault instead of being written into git, using the
same path every other chart in this repo uses:

```
Vault  secret/one2n/dev/app-config
   │        ├── db_password              ──┐
   │        ├── grafana_admin_user       ──┤
   │        └── grafana_admin_password   ──┤
   │                                       │  ClusterSecretStore "vault-backend"
   ▼                                       ▼  (from the eso-config chart)
External Secrets Operator ──────► Secret postgres-exporter-db  → postgres-exporter
                          ──────► Secret grafana-admin         → Grafana admin login
```

Until both `ExternalSecret` objects report `SecretSynced`, those two pods stay
in `CreateContainerConfigError`. That is the expected failure when
`make vault-seed` has not run.

Grafana's admin password is deliberately **not** left to the chart's random
generator: that value is regenerated on every render, which Argo CD would
report as permanent drift.

## Promtail sends application logs only

Discovery finds every pod in the cluster. One relabel rule narrows it:

```yaml
extraRelabelConfigs:
  - source_labels: [__meta_kubernetes_namespace]
    regex: student-api
    action: keep
```

Filtering here rather than at query time means those lines are never read or
transmitted: less traffic, less storage, fewer Loki streams. The trade-off is
that a failure caused by something in `kube-system` leaves no trace.

This has one non-obvious consequence, which `updateStrategy` in `values.yaml`
exists to handle: Promtail has nothing to do on nodes that run no `student-api`
pods, and an idle Promtail reports itself **unready**. The default
one-at-a-time DaemonSet rollout waits for each pod to become ready, so it stalls
forever on the first idle node. `maxUnavailable: 100%` replaces them all at
once instead.

## Notable values

| Key | Why it is set |
| --- | --- |
| `prometheus.scrapeConfigs.*.enabled: false` | Removes the chart's 10 default jobs so every job is one we wrote. `scrapeConfigs: null` does **not** work here — Helm does not propagate null-deletion into a subchart |
| `*.fullnameOverride` | Pins Service names. Otherwise Helm generates `<release>-<chart>`, and the scrape jobs that must match those names fail **silently** with zero targets |
| `storageClass: local-path` | The default `standard` binds volumes before scheduling, so on a multi-node cluster the directory is created on the wrong machine and the pod crash-loops. Requires `minikube addons enable storage-provisioner-rancher` |
| `loki.deploymentMode: SingleBinary` | The chart defaults to a 9-pod split with S3 storage and 8Gi memcached caches |
| `loki.loki.auth_enabled: false` | Means "no multi-tenancy", not "no security". Left true, every request needs an `X-Scope-OrgID` header |
| `prometheus.server.strategy.type: Recreate` | Two pods cannot mount one ReadWriteOnce volume, so a rolling update would hang in Pending |

## Maintaining the vendored dependencies

```bash
# after bumping any version pin in Chart.yaml
helm dependency build ./helm/observability
```

This re-downloads the pinned chart versions into `charts/` and updates
`Chart.lock`. Commit both — the `.tgz` files are intentionally **not**
gitignored.

## Deploying

```bash
helm upgrade --install observability ./helm/observability \
  -n observability-ns --create-namespace --wait --timeout 10m
```

Or let Argo CD do it — see `argocd-apps/application-observability.yaml`.

Always render before installing. The render is the truth; a values file is only
half of it, and Helm silently ignores keys it does not recognise:

```bash
helm template observability ./helm/observability -n observability-ns | less
```

## Verifying

```bash
# Every target UP -- expect 6 jobs, with node-exporter showing one per node
kubectl port-forward -n observability-ns svc/prometheus-server 9090:80
# → http://localhost:9090  →  Status → Target health

# Grafana, with both datasources already provisioned
kubectl get secret grafana-admin -n observability-ns -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl port-forward -n observability-ns svc/grafana 3000:80

# Application logs only
kubectl exec -n observability-ns deploy/grafana -- wget -qO- \
  'http://loki.observability-ns.svc.cluster.local:3100/loki/api/v1/label/namespace/values'
# → {"status":"success","data":["student-api"]}

# Endpoint probes: 1 = reachable
#   PromQL:  probe_success
#            probe_duration_seconds
```

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| A scrape job shows **0 targets** | The `keep` regex does not match the Service name. Cross-check `kubectl get svc -n observability-ns`. This fails silently — no error anywhere |
| A target is listed but **DOWN** | Discovery worked, scraping failed: wrong port, path, or network |
| `postgres-exporter` / `grafana` in `CreateContainerConfigError` | The `ExternalSecret` has not synced. `kubectl get externalsecret -n observability-ns` |
| Prometheus `CrashLoopBackOff` | Read the logs, not the events — a config parse error never appears in events |
| A values change had no effect | Walk the three layers: `cat` the file → `helm get values` (did `-f` land?) → `helm get manifest` (did the key take effect?) |
| Config looks right but behaviour is old | A mounted file is not the running config. Kubelet updates mounted Secrets in place, but most processes parse config once at startup. Compare pod age to `helm history` |
