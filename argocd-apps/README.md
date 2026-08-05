# argocd-apps/

The declarative half of the GitOps setup. Nothing in this folder is a workload —
it's only the Argo CD objects that describe **what** Argo CD should deploy.
Every file is a plain Kubernetes manifest, no Helm chart, no templating: read
any file top to bottom and that is exactly what gets created.

This replaces `argocd app create`, `argocd repo add`, and every other
imperative `argocd` CLI call — all of it lives in git and is reviewable in a
pull request.

## What's here

| File | Resource | Purpose |
| --- | --- | --- |
| `appproject.yaml` | AppProject `sre-bootcamp` | Only this repository may be a source, only these namespaces may be deployed into |
| `repository.yaml` | Secret `sre-bootcamp-repo` | Registers the git repository with Argo CD |
| `application-external-secrets.yaml` | Application `external-secrets` | Deploys `helm/external-secrets` → namespace `eso-ns`, wave 0 |
| `application-vault.yaml` | Application `vault` | Deploys `helm/vault` → namespace `vault`, wave 1 |
| `application-eso-config.yaml` | Application `eso-config` | Deploys `helm/eso-config` → namespace `eso-ns`, wave 2 |
| `application-postgres-db.yaml` | Application `postgres-db` | Deploys `helm/postgres-db` → namespace `student-api`, wave 3 |
| `application-student-api.yaml` | Application `student-api` | Deploys `helm/student-api` → namespace `student-api`, wave 4 |
| `application-root.yaml` | Application `sre-bootcamp-root` | The app-of-apps — points back at this folder |

Every `Application`'s source is a **chart path in this repository, plus its
`values.yaml`**. Argo CD renders that chart itself with `helm template` — it
never runs `helm install`. So the charts under `helm/` and their `values.yaml`
are the only description of what runs in the cluster; nothing here overrides
them.

`helm.releaseName` in each Application is pinned to the name Helm used when
these charts were installed by hand (`make helm-install-all`). That keeps the
rendered resource names identical, which is what lets Argo CD **adopt** an
already-deployed stack instead of creating a second copy beside it.

The `argocd.argoproj.io/sync-wave` annotation controls the order Applications
are created in — lower numbers first, and Argo CD waits for each wave to
report healthy before starting the next. That ordering only matters when the
Applications are created by the root app; applying every file by hand at once
just means Argo CD's own reconcile loop sorts out the ordering instead.

## The sync policy

Every Application repeats the same short block, so each file stays complete on
its own — nothing is inherited from elsewhere:

```yaml
syncPolicy:
  automated:
    prune: true      # delete resources removed from git
    selfHeal: true   # undo changes made with kubectl
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

`ServerSideApply` is required for the ESO CRDs, which are far too large for the
`last-applied-configuration` annotation a client-side apply writes. It's also
what lets Argo CD take over fields Helm previously owned.

Every Application also carries the `resources-finalizer`, so deleting one
deletes what it created rather than orphaning it. `make argocd-uninstall`
strips that finalizer first, precisely so removing Argo CD does not remove the
stack.

`application-external-secrets.yaml` additionally has `ignoreDifferences` for
the CA bundle that ESO's cert-controller injects into its own webhooks and
CRDs at runtime — a value that legitimately does not exist in git, and would
otherwise keep that Application permanently `OutOfSync`.

## The root Application (app-of-apps)

`application-root.yaml` is an Application whose source is *this same folder*.
Once it exists in the cluster, the files above stop being something you
`kubectl apply` by hand and become something git owns: add a new
`application-*.yaml` file here, push, and Argo CD creates it on its own.

Its source path (`argocd-apps`) has to exist on the tracked branch, so **push
this folder before applying it**:

```bash
git add argocd-apps/
git commit -m "Add Argo CD app-of-apps configuration"
git push
```

If you ever see `sre-bootcamp-root` stuck as `Unknown` with "path does not
exist", it just means you applied before pushing — push, and it clears up on
its own within about a minute (no need to re-run anything).

## Deploying

```bash
make argocd-apps-install
# equivalent to:
kubectl apply -f argocd-apps/
```

Then watch it converge:

```bash
kubectl get applications -n argocd -w
```

Argo CD deploys Vault but cannot finish bootstrapping it — Vault always comes
up sealed. Run `make vault-setup` once, and `make vault-unseal` after every
Vault pod restart.

## Tracking a different branch

`targetRevision: main` is hardcoded in every file here. To point at another
branch for local testing, without editing anything on disk:

```bash
make argocd-apps-install ARGOCD_REVISION=k8s
```

That substitutes the branch name on the fly while applying — the files in git
still say `main`.

## If your repository is private

`repository.yaml` registers a public repository, so it holds nothing secret.
For a private one, don't put a token in git — seed it into Vault and let ESO
build the Secret, the same way the app's database password works. Seed the
token:

```bash
kubectl exec -n vault vault-0 -c vault -- \
  env VAULT_TOKEN=<root-token> vault kv patch secret/one2n/dev/app-config \
  git_username=<user> git_token=<pat>
```

Then replace `repository.yaml` with:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: sre-bootcamp-repo
  namespace: argocd
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: sre-bootcamp-repo
    creationPolicy: Owner
    template:
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        type: git
        url: https://github.com/madhav-wakhare/SRE-Bootcamp.git
        username: "{{ .username }}"
        password: "{{ .password }}"
  data:
    - secretKey: username
      remoteRef: { key: one2n/dev/app-config, property: git_username }
    - secretKey: password
      remoteRef: { key: one2n/dev/app-config, property: git_token }
```

That requires the `external-secrets` and `eso-config` Applications to already
be in place, exactly like the `postgres-db` and `student-api` charts.
