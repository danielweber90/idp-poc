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
