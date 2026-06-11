ECR_REPO ?= 084375542523.dkr.ecr.eu-central-1.amazonaws.com/idp-poc/backstage
TAG      ?= latest
REGION   ?= eu-central-1

.PHONY: install build push deploy

# Install dependencies (run once, or after package.json changes)
install:
	yarn install

# Build frontend + backend
build:
	yarn workspace app build
	yarn workspace backend build

# Login to ECR and push the image
push:
	aws ecr get-login-password --region $(REGION) | \
	  podman login --username AWS --password-stdin $(ECR_REPO)
	podman build --no-cache --platform linux/amd64 \
	  -t $(ECR_REPO):$(TAG) \
	  -f packages/backend/Dockerfile .
	podman push $(ECR_REPO):$(TAG)

# Full cycle: build + push
release: build push

# Restart the Backstage pod in Kubernetes (ArgoCD will also do this on next sync)
deploy:
	kubectl rollout restart deployment/backstage -n platform-backstage
	kubectl rollout status deployment/backstage -n platform-backstage
