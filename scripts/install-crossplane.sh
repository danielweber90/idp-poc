#!/usr/bin/env bash
# Phase 3: Install Crossplane with AWS provider and apply XRDs
# Claude Code: Run after Phase 2
set -euo pipefail

MODE="${1:-aws}"   # aws | local
echo "=== Phase 3: Crossplane Setup (mode: $MODE) ==="

echo "--> Installing Crossplane..."
helm repo add crossplane-stable https://charts.crossplane.io/stable --force-update 2>/dev/null || true
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --create-namespace \
  --set args='{"--enable-composition-functions"}' \
  --wait --timeout 120s

echo "--> Waiting for Crossplane pods..."
kubectl -n crossplane-system rollout status deployment/crossplane --timeout=120s

if [[ "$MODE" == "aws" ]]; then
  echo "--> Installing AWS provider..."
  kubectl apply -f - <<PROVIDER
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws-rds
spec:
  package: xpkg.upbound.io/upbound/provider-aws-rds:v1.14.0
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws-s3
spec:
  package: xpkg.upbound.io/upbound/provider-aws-s3:v1.14.0
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws-elasticache
spec:
  package: xpkg.upbound.io/upbound/provider-aws-elasticache:v1.14.0
PROVIDER

  echo "--> Waiting for providers to become healthy (may take 2-3 min)..."
  sleep 30
  kubectl wait provider/provider-aws-rds --for=condition=Healthy --timeout=180s
  kubectl wait provider/provider-aws-s3  --for=condition=Healthy --timeout=180s

  echo "--> Creating ProviderConfig (uses IRSA / pod identity)..."
  kubectl apply -f - <<PCONFIG
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: IRSA
PCONFIG

else
  echo "--> Installing Kubernetes provider (for local in-cluster resources)..."
  kubectl apply -f - <<PROVIDER
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-kubernetes
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v0.14.1
PROVIDER
  kubectl wait provider/provider-kubernetes --for=condition=Healthy --timeout=180s
fi

echo "--> Applying XRDs..."
kubectl apply -f ../infrastructure/crossplane/xrds/

echo "--> Applying Compositions for mode: $MODE..."
kubectl apply -f "../infrastructure/crossplane/compositions/${MODE}/"

echo ""
echo "=== Phase 3 complete ==="
echo "Test with: kubectl get xrds"
echo "Test with: kubectl apply -f infrastructure/crossplane/test-claims/"
