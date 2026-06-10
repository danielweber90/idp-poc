#!/usr/bin/env bash
set -euo pipefail
echo "=== Phase 5: Backstage ==="
kubectl create namespace platform-backstage --dry-run=client -o yaml | kubectl apply -f -
ARGOCD_PW=
kubectl -n platform-backstage create secret generic backstage-secrets \
  --from-literal=GITHUB_TOKEN="${IDP_POC_GITHUB_TOKEN}" \
  --from-literal=GITHUB_ORG="${IDP_POC_GITHUB_ORG}" \
  --from-literal=POSTGRES_HOST="backstage-db" \
  --from-literal=POSTGRES_PORT="5432" \
  --from-literal=POSTGRES_USER="backstage" \
  --from-literal=POSTGRES_PASSWORD="backstage-poc-pw" \
  --from-literal=ARGOCD_AUTH_TOKEN="$ARGOCD_PW" \
  --from-literal=K8S_SA_TOKEN="" \
  --dry-run=client -o yaml | kubectl apply -f -
helm repo add backstage https://backstage.github.io/charts --force-update 2>/dev/null || true
helm upgrade --install backstage backstage/backstage \
  --namespace platform-backstage \
  --values ../platform/backstage/values-poc.yaml \
  --wait --timeout 180s
echo "Access: kubectl -n platform-backstage port-forward svc/backstage 7007:7007"
