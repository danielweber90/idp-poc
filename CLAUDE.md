# IDP PoC — Claude Code Instructions

## Project Goal
Build a minimal but complete Internal Developer Platform (IDP) PoC that demonstrates the full
developer experience end-to-end:

  git push → CI → ArgoCD deploys → Backstage shows status → Crossplane provisions backing services

## Target Environments
- **Primary (AWS):** EKS cluster as Control Plane  ← preferred
- **Fallback (Local):** kind cluster via Podman

## Architecture Overview
```
Control Plane (EKS or kind)
├── ArgoCD          — GitOps deployment engine
├── Crossplane      — Infrastructure abstraction (backing services)
├── Backstage       — Developer portal (catalog + templates)
├── Kong            — API gateway
└── kube-prometheus-stack + Loki  — Observability

Backing Services (provisioned by Crossplane)
├── PostgreSQL      — AWS RDS (on AWS) / in-cluster CloudNativePG (local)
├── Redis           — AWS ElastiCache (on AWS) / in-cluster Redis (local)
└── S3 Bucket       — AWS S3 (on AWS) / MinIO (local)

Demo App
└── Node.js Express API — connects to PostgreSQL + Redis, reads/writes S3
```

## Repository Layout
```
idp-poc/
├── CLAUDE.md                        ← YOU ARE HERE — start here always
├── RUNBOOK.md                       ← Step-by-step human runbook
├── infrastructure/
│   ├── tofu/                        ← OpenTofu: EKS + VPC + RDS + ElastiCache
│   ├── crossplane/
│   │   ├── xrds/                    ← CompositeResourceDefinitions (developer API)
│   │   └── compositions/            ← Translations to AWS or local services
│   ├── argocd/                      ← ArgoCD Application manifests
│   └── kong/                        ← Kong Ingress + KongPlugin manifests
├── platform/
│   ├── backstage/                   ← Backstage Helm values + catalog entities
│   └── observability/               ← kube-prometheus-stack + Loki values
├── apps/
│   └── demo-app/                    ← The demo Node.js application
│       ├── src/                     ← Application source code
│       ├── helm/                    ← Helm chart for Kubernetes deployment
│       └── catalog-info.yaml        ← Backstage catalog entry
└── scripts/                         ← Helper shell scripts
```

## Task Phases

### Phase 0 — Prerequisites Check
File: `scripts/check-prerequisites.sh`
Task: Verify all required tools are installed and configured.

### Phase 1 — Infrastructure Bootstrap (AWS path)
Files: `infrastructure/tofu/`
Task: Use OpenTofu to create EKS cluster, VPC, RDS, ElastiCache, S3 bucket.

### Phase 1b — Infrastructure Bootstrap (Local path)
Files: `scripts/bootstrap-local.sh`
Task: Create kind cluster with Podman, install MinIO + CloudNativePG + Redis operator.

### Phase 2 — Platform Installation
Files: `infrastructure/argocd/`, `platform/observability/`, `infrastructure/kong/`
Task: Install ArgoCD, kube-prometheus-stack, Loki, Kong via Helm.

### Phase 3 — Crossplane Setup
Files: `infrastructure/crossplane/`
Task: Install Crossplane, configure AWS provider, apply XRDs and Compositions.

### Phase 4 — Demo App Deployment
Files: `apps/demo-app/`
Task: Build and deploy demo app via ArgoCD. Verify end-to-end.

### Phase 5 — Backstage Setup
Files: `platform/backstage/`
Task: Deploy Backstage, register demo app in catalog, verify all plugins show data.

## Key Conventions

### Naming
- Cluster name: `idp-poc`
- AWS region: `eu-central-1` (Frankfurt) — closest to Germany
- Namespace pattern: `platform-*` for infra, `team-demo` for app teams
- All resources tagged: `project=idp-poc`, `managed-by=opentofu`

### Secrets Handling (PoC-grade)
- AWS credentials: via environment variables or AWS CLI profile
- Kubernetes secrets: created directly via kubectl (no Vault in PoC)
- Crossplane ProviderConfig: uses IRSA (IAM Roles for Service Accounts) on AWS

### Helm Values Pattern
All Helm installations use a `values-poc.yaml` override file in the relevant directory.
Never modify upstream chart defaults directly.

### Crossplane XRD Convention
- Developer API group: `platform.idp-poc.io`
- All XRDs follow the pattern: `<Resource>Claim` (namespaced) + `<Resource>Instance` (cluster)
- Connection secrets are always written to the app's namespace

## How to Use These Instructions with Claude Code

1. **Start every session** by reading this CLAUDE.md
2. **Read the relevant phase files** before starting work on a phase
3. **Check RUNBOOK.md** for the current status of what's been completed
4. **Run prerequisite checks** before any phase
5. **Commit after each successful phase** with message: `feat: phase-N complete`

## Environment Variables Required
```bash
# AWS (for AWS path)
AWS_REGION=eu-central-1
AWS_ACCOUNT_ID=<your-account-id>
AWS_PROFILE=<your-profile>          # or use AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY

# PoC Config
IDP_POC_DOMAIN=idp-poc.local        # for local; replace with real domain on AWS
IDP_POC_GITHUB_ORG=<your-github-org>
IDP_POC_GITHUB_TOKEN=<your-pat>     # needs: repo, read:org, read:user
```

## Definition of Done (PoC)
- [ ] Developer runs Backstage template wizard → fills in app name + backing services
- [ ] Template creates: Git repo skeleton + Helm chart + Crossplane claims + ArgoCD app
- [ ] ArgoCD syncs automatically → app runs in `team-demo` namespace
- [ ] Crossplane provisions PostgreSQL + Redis → connection secrets appear in namespace
- [ ] App is reachable via Kong API Gateway
- [ ] Grafana shows app metrics (request rate, latency, error rate)
- [ ] Loki shows app logs in Grafana
- [ ] Backstage catalog shows: K8s pod status + ArgoCD sync + Grafana dashboard link
