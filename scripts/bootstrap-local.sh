#!/usr/bin/env bash
# Phase 1b: Bootstrap local kind cluster with Podman
# Claude Code: Use this when no AWS access available
set -euo pipefail

CLUSTER_NAME="idp-poc"

echo "==> Creating kind cluster (Podman driver)..."
export KIND_EXPERIMENTAL_PROVIDER=podman
cat <<KINDCFG | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 8080
        protocol: TCP
      - containerPort: 443
        hostPort: 8443
        protocol: TCP
  - role: worker
  - role: worker
KINDCFG

kubectl config use-context "kind-$CLUSTER_NAME"
echo "Cluster context: kind-$CLUSTER_NAME"

echo "==> Installing MinIO (S3-compatible object storage)..."
helm repo add minio https://charts.min.io/ --force-update 2>/dev/null || true
helm upgrade --install minio minio/minio \
  --namespace minio --create-namespace \
  --set rootUser=minioadmin,rootPassword=minioadmin \
  --set mode=standalone \
  --set persistence.size=2Gi \
  --set resources.requests.memory=256Mi \
  --wait --timeout 120s

echo "==> Installing CloudNativePG operator (PostgreSQL)..."
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update 2>/dev/null || true
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system --create-namespace \
  --wait --timeout 120s

echo "==> Creating demo PostgreSQL cluster..."
kubectl apply -f - <<PGCLUSTER
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: demo-db
  namespace: default
spec:
  instances: 1
  storage:
    size: 1Gi
  bootstrap:
    initdb:
      database: demoapp
      owner: demouser
PGCLUSTER

echo "==> Installing Redis..."
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null || true
helm upgrade --install redis bitnami/redis \
  --namespace redis-system --create-namespace \
  --set auth.enabled=false \
  --set architecture=standalone \
  --set master.persistence.size=1Gi \
  --wait --timeout 120s

echo ""
echo "=== Local cluster ready ==="
echo "MinIO:      kubectl -n minio port-forward svc/minio-console 9001:9001"
echo "PostgreSQL: demo-db-rw.default.svc.cluster.local:5432"
echo "Redis:      redis-master.redis-system.svc.cluster.local:6379"
