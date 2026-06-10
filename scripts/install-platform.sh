#!/usr/bin/env bash
# Phase 2: Install ArgoCD, Observability stack, Kong
# Claude Code: Run after Phase 1 cluster bootstrap
set -euo pipefail

echo "=== Phase 2: Platform Installation ==="

# ── ArgoCD ────────────────────────────────────────────────────────────────────
echo "--> Installing ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update 2>/dev/null || true
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --values ../infrastructure/argocd/values-poc.yaml \
  --wait --timeout 180s

echo "ArgoCD password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# ── kube-prometheus-stack ─────────────────────────────────────────────────────
echo "--> Installing kube-prometheus-stack (Prometheus + Grafana + Alertmanager)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update 2>/dev/null || true
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace platform-monitoring --create-namespace \
  --values ../platform/observability/prometheus-values-poc.yaml \
  --wait --timeout 300s

# ── Loki ─────────────────────────────────────────────────────────────────────
echo "--> Installing Loki + Promtail..."
helm repo add grafana https://grafana.github.io/helm-charts --force-update 2>/dev/null || true
helm upgrade --install loki grafana/loki \
  --namespace platform-monitoring \
  --values ../platform/observability/loki-values-poc.yaml \
  --wait --timeout 180s

helm upgrade --install promtail grafana/promtail \
  --namespace platform-monitoring \
  --set config.lokiAddress=http://loki:3100/loki/api/v1/push \
  --wait

# ── Kong ─────────────────────────────────────────────────────────────────────
echo "--> Installing Kong API Gateway..."
helm repo add kong https://charts.konghq.com --force-update 2>/dev/null || true
helm upgrade --install kong kong/ingress \
  --namespace kong --create-namespace \
  --values ../infrastructure/kong/values-poc.yaml \
  --wait --timeout 120s

echo ""
echo "=== Phase 2 complete ==="
echo "Port-forwards to access UIs:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "  kubectl -n platform-monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80"
echo "  kubectl -n kong port-forward svc/kong-proxy 8000:80"
