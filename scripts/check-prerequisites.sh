#!/usr/bin/env bash
# Phase 0: Check all required tools are installed
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ERRORS=0

check() {
  local tool=$1 cmd=$2 hint=$3
  if command -v "$tool" &>/dev/null; then
    local ver; ver=$(eval "$cmd" 2>/dev/null | head -1 || echo "unknown")
    echo -e "${GREEN}OK${NC}  $tool  ($ver)"
  else
    echo -e "${RED}MISSING${NC}  $tool  -- install hint: $hint"
    ERRORS=$((ERRORS+1))
  fi
}

check_env() {
  local var=$1
  if [[ -n "${!var:-}" ]]; then
    echo -e "${GREEN}OK${NC}  $var = ${!var}"
  else
    echo -e "${YELLOW}WARN${NC}  $var is not set"
  fi
}

echo "=== IDP PoC - Prerequisites Check ==="
echo ""
echo "-- Core Tools --"
check kubectl  "kubectl version --client --short 2>/dev/null || kubectl version --client" "brew install kubectl"
check helm     "helm version --short"       "brew install helm"
check tofu     "tofu --version"             "brew install opentofu"
check git      "git --version"              "brew install git"
check jq       "jq --version"              "brew install jq"

echo ""
echo "-- AWS Path --"
check aws      "aws --version"             "brew install awscli"
check eksctl   "eksctl version"            "brew install eksctl"

echo ""
echo "-- Local Path (Podman + kind) --"
check podman   "podman --version"          "brew install podman"
check kind     "kind --version"            "brew install kind"

echo ""
echo "-- Environment Variables --"
check_env AWS_REGION
check_env AWS_ACCOUNT_ID
check_env IDP_POC_GITHUB_ORG
check_env IDP_POC_GITHUB_TOKEN

echo ""
echo "-- AWS Authentication --"
if command -v aws &>/dev/null; then
  if aws sts get-caller-identity &>/dev/null 2>&1; then
    ID=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo "unknown")
    echo -e "${GREEN}OK${NC}  AWS authenticated as: $ID"
  else
    echo -e "${YELLOW}WARN${NC}  AWS not authenticated (run: aws configure  or  aws sso login)"
  fi
fi

echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}$ERRORS tool(s) missing. Install before continuing.${NC}"
  exit 1
else
  echo -e "${GREEN}All tools present. Ready to proceed.${NC}"
fi
