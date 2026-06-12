# IDP PoC — Runbook

Track phase completion here. Update checkboxes as you work.

## Status
- [x] Phase 0 - Prerequisites verified
- [x] Phase 1 - EKS cluster running (or: kind cluster running)
- [x] Phase 2 - Platform installed (ArgoCD, Observability, Kong)
- [x] Phase 3 - Crossplane running, XRDs applied
- [x] Phase 4 - Demo app deployed via ArgoCD
- [x] Phase 5 - Backstage running, catalog populated

## Environment (fill in as you go)
```
Cluster type:     AWS EKS
Cluster name:     idp-poc
Region:           eu-central-1
kubectl context:  arn:aws:eks:eu-central-1:084375542523:cluster/idp-poc
Backstage URL:    https://idp-poc.impact-tracking.dev.uptimize.merckgroup.com/backstage
ArgoCD URL:       https://idp-poc.impact-tracking.dev.uptimize.merckgroup.com/argocd
Grafana URL:      https://idp-poc.impact-tracking.dev.uptimize.merckgroup.com/grafana  (admin / idp-poc-admin)
Kong proxy URL:   https://idp-poc.impact-tracking.dev.uptimize.merckgroup.com
Demo app URL:     https://idp-poc.impact-tracking.dev.uptimize.merckgroup.com/demo
```

## Updating Platform Components

All platform components are managed by ArgoCD. To update any component:
1. Edit its values file in this repo
2. `git push` — ArgoCD syncs automatically (polls every 3 min, or click Sync in the UI)

| Component | Values file |
|---|---|
| Backstage | `platform/backstage/values-poc.yaml` |
| Grafana / Prometheus | `platform/observability/prometheus-values-poc.yaml` |
| Loki | `platform/observability/loki-values-poc.yaml` |
| Kong | `infrastructure/kong/values-poc.yaml` |
| Demo app | `apps/demo-app/helm/values.yaml` |

### Updating Backstage secrets (tokens, passwords)

Secrets are NOT in Git. To rotate a secret:
```bash
kubectl create secret generic backstage-secrets \
  -n platform-backstage \
  --from-literal=GITHUB_TOKEN="<token>" \
  --from-literal=GITHUB_ORG="danielweber90" \
  --from-literal=GITHUB_CLIENT_SECRET="<secret>" \
  --from-literal=K8S_SA_TOKEN="$(kubectl get secret backstage-sa-token \
      -n platform-backstage -o jsonpath='{.data.token}' | base64 -d)" \
  --from-literal=ARGOCD_AUTH_TOKEN="$(kubectl -n argocd get secret \
      argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/backstage -n platform-backstage
```

### How to modify and rebuild the Backstage image

The Backstage source lives at `platform/backstage/app/`. A `Makefile` wraps the build workflow.

**Key files to edit:**

| File | What it controls |
|---|---|
| `packages/backend/src/index.ts` | Backend plugins (add/remove `backend.add(import(...))`) |
| `packages/app/src/App.tsx` | Frontend plugins |
| `packages/app/src/modules/nav/Sidebar.tsx` | Sidebar layout |
| `packages/*/package.json` | Plugin dependencies |

**Workflow:**
```bash
cd platform/backstage/app

# 1. Edit the source files

# 2. If you added a new package dependency:
yarn install

# 3. Build frontend + backend, then push to ECR:
make release
# (equivalent to: yarn workspace app build && yarn workspace backend build
#                 && podman build ... && podman push ...)

# 4. Commit the source changes and push:
cd ../../..
git add platform/backstage/
git commit -m "feat: add XYZ plugin to Backstage"
git push

# 5. Restart the pod to pull the new image:
kubectl rollout restart deployment/backstage -n platform-backstage
```

Config-only changes (auth providers, catalog locations, URLs) only need a
`values-poc.yaml` edit + `git push` — no image rebuild required.

## Adding a New App Repo to ArgoCD (SSH deploy key)

Each app in its own repo uses an SSH deploy key. The key pair and ArgoCD Application
manifest live together in `apps/<app-name>.yaml` in this repo.

### Structure of `apps/<app-name>.yaml`

```yaml
# Wave 1: register the SSH credential before ArgoCD tries to clone the repo
apiVersion: v1
kind: Secret
metadata:
  name: <app>-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
  annotations:
    argocd.argoproj.io/sync-wave: "1"
type: Opaque
stringData:
  type: git
  url: git@github.com:<org>/<repo>.git
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    <private key content>
    -----END OPENSSH PRIVATE KEY-----
---
# Wave 2: the Application itself (runs after the secret is applied)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app>
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: default
  source:
    repoURL: git@github.com:<org>/<repo>.git
    targetRevision: main
    path: helm
    helm:
      releaseName: <app>
      valueFiles: [values.yaml]
  destination:
    server: https://kubernetes.default.svc
    namespace: team-<name>
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
```

The `customer-apps` ArgoCD Application watches the `apps/` directory and automatically
picks up any new file added there.

### Generating a deploy key

```bash
ssh-keygen -t ed25519 -f deploy_key -N "" -C "argocd-deploy-key"
# deploy_key      ← private key (goes in the YAML above)
# deploy_key.pub  ← public key  (add to GitHub repo: Settings → Deploy keys)
```

### Rotating a deploy key

1. Generate a new keypair (see above)
2. Add `deploy_key.pub` to the GitHub repo's **Settings → Deploy keys**
3. Update `sshPrivateKey` in `apps/<app-name>.yaml` with the new private key
4. `git push` → `customer-apps` picks it up and applies the updated secret automatically

### Troubleshooting "repository not found"

This error always means a key mismatch. Verify with:

```bash
# Check what key ArgoCD is using (get its fingerprint)
kubectl get secret <app>-repo -n argocd \
  -o jsonpath='{.data.sshPrivateKey}' | base64 -d > /tmp/k && \
chmod 600 /tmp/k && ssh-keygen -l -f /tmp/k && rm /tmp/k

# Compare with the local deploy_key fingerprint
ssh-keygen -l -f deploy_key

# Test the key against GitHub directly
GIT_SSH_COMMAND="ssh -i deploy_key -o StrictHostKeyChecking=no" \
  git ls-remote git@github.com:<org>/<repo>.git HEAD
```

If fingerprints don't match: update `apps/<app-name>.yaml`, push, then hard-refresh
`customer-apps` in ArgoCD and restart the repo-server:
```bash
kubectl -n argocd annotate application customer-apps argocd.argoproj.io/refresh=hard --overwrite
kubectl rollout restart deployment/argocd-repo-server -n argocd
```

> **Note:** `selfHeal: true` on `customer-apps` means any manual `kubectl patch` to the
> secret will be reverted within seconds. Always fix the key in the YAML file and push.

## Useful Commands
```bash
# ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port-forwards (run each in a separate terminal)
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n platform-monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80
kubectl -n platform-backstage port-forward svc/backstage 7007:7007
kubectl -n kong port-forward svc/kong-proxy 8000:80
```
