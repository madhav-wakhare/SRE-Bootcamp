# argocd-apps

The declarative half of the GitOps setup. This chart contains no workload of its
own — only the Argo CD objects that describe **what** Argo CD should deploy. It
replaces `argocd app create`, `argocd repo add`, and every other imperative
`argocd` CLI call: all of it lives in git and is reviewable in a pull request.

Install it once to bootstrap. After that its own root Application keeps it in
sync with git.

## What this chart creates

One file per object, each a plain manifest you can read top to bottom:

| Template | Resource | Purpose |
| --- | --- | --- |
| `appproject.yaml` | AppProject `sre-bootcamp` | Only this repository may be a source, only the four listed namespaces may be deployed into |
| `repository.yaml` | Secret `argocd-apps-repo` | Registers the git repository with Argo CD |
| `application-external-secrets.yaml` | Application `external-secrets` | `helm/external-secrets` → namespace `eso-ns`, wave 0 |
| `application-vault.yaml` | Application `vault` | `helm/vault` → namespace `vault`, wave 1 |
| `application-eso-config.yaml` | Application `eso-config` | `helm/eso-config` → namespace `eso-ns`, wave 2 |
| `application-postgres-db.yaml` | Application `postgres-db` | `helm/postgres-db` → namespace `student-api`, wave 3 |
| `application-student-api.yaml` | Application `student-api` | `helm/student-api` → namespace `student-api`, wave 4 |
| `application-root.yaml` | Application `sre-bootcamp-root` | The app-of-apps, pointing back at this chart |

Every Application's source is a **chart path in this repository plus its
`values.yaml`** — Argo CD renders the chart with `helm template` itself, so the
charts and their values are the only description of what runs in the cluster.

Sync waves order the Applications relative to each other, but only when they are
created by the root Application. A plain `helm install` of this chart creates
them all at once and Argo CD's reconcile loop sorts the ordering out instead.

`helm.releaseName` is pinned to the Application name so the rendered resource
names stay identical to the ones `make helm-install-all` produced. That is what
lets Argo CD **adopt** an already-deployed stack instead of creating a second
copy beside it.

## The sync policy

Every Application repeats the same short block, so each file is complete on its
own:

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
`last-applied-configuration` annotation a client-side apply writes. It is also
what lets Argo CD take over fields previously owned by Helm.

Each Application also carries the `resources-finalizer`, so deleting one deletes
what it created rather than orphaning it. `make argocd-uninstall` strips that
finalizer first, precisely so removing Argo CD does not remove the stack.

`application-external-secrets.yaml` additionally has `ignoreDifferences` for the
CA bundle that ESO's cert-controller injects into its own webhooks and CRDs at
runtime — a value that legitimately does not exist in git, and would otherwise
keep the Application permanently `OutOfSync`.

## The root Application (app-of-apps)

`rootApp: true` (the default) creates `sre-bootcamp-root`, an Application whose
source is *this chart*. After the bootstrap install, the Applications stop being
something you `helm upgrade` and become something git owns: add a new
`application-*.yaml` file, push, and Argo CD creates it by itself.

The path it points at (`helm/argocd-apps`) has to exist on the tracked branch,
so keep it off until this chart has actually been pushed:

```bash
make argocd-apps-install ARGOCD_APPS_EXTRA='--set rootApp=false'
```

## Values

| Key | Default | Notes |
| --- | --- | --- |
| `repoURL` | `https://github.com/madhav-wakhare/SRE-Bootcamp.git` | Also the only entry in the AppProject's `sourceRepos` |
| `targetRevision` | `main` | The branch Argo CD tracks. Must be the branch CI commits the image tag to. Override with `make argocd-apps-install ARGOCD_REVISION=<branch>` |
| `project` | `sre-bootcamp` | AppProject name |
| `namespaces` | `argocd, eso-ns, vault, student-api` | Namespaces the project may deploy into |
| `rootApp` | `true` | Turn off for the very first install |

## If your repository is private

`repository.yaml` registers a public repository, so it holds nothing secret. For
a private one, do not put a token in git — seed it into Vault and let ESO build
the Secret, the same way the app's database password works. Seed the token:

```bash
kubectl exec -n vault vault-0 -c vault -- \
  env VAULT_TOKEN=<root-token> vault kv patch secret/one2n/dev/app-config \
  git_username=<user> git_token=<pat>
```

Then replace `templates/repository.yaml` with:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ .Release.Name }}-repo
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: {{ .Release.Name }}-repo
    creationPolicy: Owner
    template:
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        type: git
        url: {{ .Values.repoURL | quote }}
        username: "{{ `{{ .username }}` }}"
        password: "{{ `{{ .password }}` }}"
  data:
    - secretKey: username
      remoteRef: { key: one2n/dev/app-config, property: git_username }
    - secretKey: password
      remoteRef: { key: one2n/dev/app-config, property: git_token }
```

That requires the `external-secrets` and `eso-config` releases to be in place,
exactly like the `postgres-db` and `student-api` charts.

## Deploying

```bash
make argocd-apps-install
# equivalent to:
helm upgrade --install argocd-apps ./helm/argocd-apps -n argocd --wait
```

Then watch it converge:

```bash
kubectl get applications -n argocd -w
```

Argo CD deploys Vault but cannot finish bootstrapping it: Vault comes up sealed.
Run `make vault-setup` once, and `make vault-unseal` after every Vault pod
restart.
