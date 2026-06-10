# IDP PoC — Runbook

Track phase completion here. Update checkboxes as you work.

## Status
- [ ] Phase 0 - Prerequisites verified
- [ ] Phase 1 - EKS cluster running (or: kind cluster running)
- [ ] Phase 2 - Platform installed (ArgoCD, Observability, Kong)
- [ ] Phase 3 - Crossplane running, XRDs applied
- [ ] Phase 4 - Demo app deployed via ArgoCD
- [ ] Phase 5 - Backstage running, catalog populated

## Environment (fill in as you go)
```
Cluster type:     [ AWS EKS | kind ]
Cluster name:     idp-poc
Region:           eu-central-1
kubectl context:  (fill in after bootstrap)
Backstage URL:    (fill in after Phase 5)
ArgoCD URL:       (fill in after Phase 2)
Grafana URL:      (fill in after Phase 2)
Kong proxy URL:   (fill in after Phase 2)
Demo app URL:     (fill in after Phase 4)
```

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
