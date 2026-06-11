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
Backstage URL:    http://ab8d1efe13ac04f1f8fd382b3aabd806-1571709816.eu-central-1.elb.amazonaws.com/backstage
ArgoCD URL:       http://ab8d1efe13ac04f1f8fd382b3aabd806-1571709816.eu-central-1.elb.amazonaws.com/argocd
Grafana URL:      http://ab8d1efe13ac04f1f8fd382b3aabd806-1571709816.eu-central-1.elb.amazonaws.com/grafana  (admin / idp-poc-admin)
Kong proxy URL:   ab8d1efe13ac04f1f8fd382b3aabd806-1571709816.eu-central-1.elb.amazonaws.com
Demo app URL:     http://ab8d1efe13ac04f1f8fd382b3aabd806-1571709816.eu-central-1.elb.amazonaws.com/demo
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
