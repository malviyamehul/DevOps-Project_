# OpsForge Infrastructure

Terraform + Ansible + Kubernetes manifests for the OpsForge platform.
Manages two environments (staging, production) on AWS EKS.

---

## Architecture Overview

```
┌─────────────────── AWS Account ──────────────────────────────────────┐
│                                                                        │
│  ┌── VPC 10.1.0.0/16 (staging) ──┐   ┌── VPC 10.2.0.0/16 (prod) ──┐ │
│  │  Public subnets  → ALB        │   │  Public subnets  → ALB      │ │
│  │  Private subnets → EKS nodes  │   │  Private subnets → EKS nodes│ │
│  │  Database subnets → RDS       │   │  Database subnets → RDS     │ │
│  │                                │   │                              │ │
│  │  EKS: t3.medium (2 nodes)     │   │  EKS: m5.large (3+ nodes)   │ │
│  │  RDS: db.t3.small  single-AZ  │   │  RDS: db.m5.large multi-AZ  │ │
│  │  Redis: cache.t3.micro x1     │   │  Redis: cache.m5.large x2   │ │
│  │  NAT: 1 shared                │   │  NAT: 1 per AZ              │ │
│  └───────────────────────────────┘   └─────────────────────────────┘ │
│                                                                        │
│  ECR repositories (shared):  opsforge/{user,task,notification,frontend}│
│  S3: tfstate-staging  tfstate-production  assets-staging  assets-prod  │
└────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
opsforge-infra/
├── terraform/
│   ├── modules/
│   │   ├── vpc/          # VPC, subnets, NAT, flow logs
│   │   ├── eks/          # EKS cluster, node groups, OIDC, add-ons
│   │   ├── rds/          # PostgreSQL, secret, parameter group
│   │   ├── elasticache/  # Redis replication group
│   │   ├── sqs/          # Queue + DLQ + policy
│   │   ├── ecr/          # Repositories + lifecycle policies
│   │   └── iam/          # IRSA roles per service + CI/CD role
│   └── environments/
│       ├── staging/      # main.tf  variables.tf  staging.tfvars  outputs.tf
│       └── production/   # main.tf  variables.tf  production.tfvars  outputs.tf
│
├── ansible/
│   ├── site.yml          # Master playbook (runs all roles)
│   ├── roles/
│   │   ├── common/       # Verify tools, update kubeconfig, add helm repos
│   │   ├── eks-tooling/  # ALB controller, Cluster Autoscaler, Metrics Server, Fluent Bit
│   │   ├── prometheus/   # kube-prometheus-stack, ServiceMonitors, Alertmanager
│   │   └── argocd/       # ArgoCD, Argo Rollouts, Application resource
│   └── inventories/
│       ├── staging/      # hosts.yml + group_vars/all.yml
│       └── production/   # hosts.yml + group_vars/all.yml
│
└── kubernetes/
    ├── base/             # Service definitions — env-agnostic
    │   ├── user-service/
    │   ├── task-service/
    │   ├── notification-service/
    │   ├── frontend/
    │   └── ingress.yaml
    ├── overlays/
    │   ├── staging/      # kustomization.yaml — patches for staging
    │   └── production/   # kustomization.yaml + rollout-task-service.yaml
    └── argocd/
        └── applications.yaml
```

---

## Prerequisites

Install these tools before running anything:

```bash
# Terraform
brew install terraform       # or: https://developer.hashicorp.com/terraform/install

# AWS CLI
brew install awscli
aws configure                # set access key, secret, region

# kubectl
brew install kubectl

# Helm
brew install helm

# Ansible
pip install ansible
ansible-galaxy collection install kubernetes.core

# kustomize (optional, kubectl has it built in)
brew install kustomize
```

---

## Step 1 — Bootstrap Terraform State Backends

These S3 buckets and DynamoDB tables must exist BEFORE running Terraform.
Run this once manually per environment:

```bash
# Staging
aws s3api create-bucket \
  --bucket opsforge-tfstate-staging \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket opsforge-tfstate-staging \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket opsforge-tfstate-staging \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name opsforge-tfstate-lock-staging \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

# Repeat for production (change bucket/table names)
```

---

## Step 2 — Terraform: Provision Infrastructure

### Staging

```bash
cd terraform/environments/staging

terraform init
terraform validate
terraform plan -var-file=staging.tfvars -out=staging.plan
terraform apply staging.plan

# Save outputs for Ansible
terraform output -json > staging-outputs.json
```

### Production (only after staging is validated)

```bash
cd terraform/environments/production

terraform init
terraform validate
terraform plan -var-file=production.tfvars -out=production.plan

# MANUAL APPROVAL required here — review the plan before applying
terraform apply production.plan

terraform output -json > production-outputs.json
```

---

## Step 3 — Ansible: Configure the Cluster

Ansible runs against `localhost` and uses `kubectl`/`helm` CLI.
All variables come from `group_vars/all.yml` + environment variables for secrets.

```bash
cd ansible/

# Export required env vars (populate from Terraform outputs)
export GRAFANA_ADMIN_PASSWORD="your-secure-password"
export ARGOCD_ADMIN_PASSWORD_BCRYPT=$(htpasswd -nbBC 10 "" your-password | tr -d ':\n' | sed 's/$2y/$2a/')
export GITOPS_REPO_URL="https://github.com/YOUR_ORG/opsforge-infra.git"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
export ALB_CONTROLLER_ROLE_ARN="arn:aws:iam::123456789:role/opsforge-staging-alb-controller"
export CLUSTER_AUTOSCALER_ROLE_ARN="arn:aws:iam::123456789:role/opsforge-staging-cluster-autoscaler"

# Run for staging
ansible-playbook site.yml -i inventories/staging/hosts.yml -v

# Run for production (after staging passes)
ansible-playbook site.yml -i inventories/production/hosts.yml -v

# Run a single role only
ansible-playbook site.yml -i inventories/staging/hosts.yml --tags prometheus
```

---

## Step 4 — Update Kustomize Overlays

Before ArgoCD can deploy, update the placeholder values in the overlays:

```bash
# Replace placeholder account ID and ARNs with real values from Terraform output
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Staging overlay
sed -i "s/123456789/${ACCOUNT_ID}/g" kubernetes/overlays/staging/kustomization.yaml

# Production overlay
sed -i "s/123456789/${ACCOUNT_ID}/g" kubernetes/overlays/production/kustomization.yaml
sed -i "s/YOUR-CERT-ID/your-acm-cert-id/g" kubernetes/overlays/production/kustomization.yaml

# Validate kustomize builds correctly
kubectl kustomize kubernetes/overlays/staging | head -50
kubectl kustomize kubernetes/overlays/production | head -50
```

---

## Step 5 — Bootstrap ArgoCD Applications

```bash
# Connect to the cluster
aws eks update-kubeconfig --region us-east-1 --name opsforge-staging

# Apply the ArgoCD Application resources
kubectl apply -f kubernetes/argocd/applications.yaml

# Watch sync status
kubectl get applications -n argocd
argocd app list    # requires argocd CLI

# Trigger manual sync
argocd app sync opsforge-staging
```

---

## Step 6 — Push Images and Trigger First Deployment

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin ${REGISTRY}

# Build and push all services (example for user-service)
docker build -t opsforge/user-service:v1.0.0 ./user-service
docker tag opsforge/user-service:v1.0.0 ${REGISTRY}/opsforge/user-service:v1.0.0
docker push ${REGISTRY}/opsforge/user-service:v1.0.0

# Update the image tag in the overlay (CI does this automatically)
cd kubernetes/overlays/staging
kustomize edit set image \
  REGISTRY/opsforge/user-service=${REGISTRY}/opsforge/user-service:v1.0.0

# Commit and push — ArgoCD picks it up automatically
git add . && git commit -m "deploy: user-service v1.0.0 to staging"
git push
```

---

## Canary Deployment (Production)

The `task-service` in production uses Argo Rollouts for canary delivery.

```bash
# Watch the rollout progress
kubectl argo rollouts get rollout task-service -n opsforge --watch

# Promote manually (skip remaining pause steps)
kubectl argo rollouts promote task-service -n opsforge

# Abort and roll back
kubectl argo rollouts abort task-service -n opsforge
kubectl argo rollouts undo task-service -n opsforge
```

The rollout auto-aborts if Prometheus detects:
- HTTP success rate drops below 95%
- p99 latency exceeds 500ms

---

## Key Terraform Commands

```bash
# See what will change without applying
terraform plan -var-file=staging.tfvars

# Destroy staging (CAREFUL)
terraform destroy -var-file=staging.tfvars

# Target a specific resource
terraform apply -target=module.rds -var-file=staging.tfvars

# Import an existing resource
terraform import module.rds.aws_db_instance.this my-existing-db

# Show current state
terraform show
terraform state list
```

---

## Secrets Management

No secrets are stored in git or Kubernetes Secrets.

| Secret | Location | How pods access it |
|---|---|---|
| DB credentials | AWS Secrets Manager | Init container via IRSA |
| JWT secret | AWS Secrets Manager | Init container via IRSA |
| Redis auth token | ElastiCache (managed) | VPC network only |
| SMTP credentials | AWS Secrets Manager | notification-service via IRSA |
| ArgoCD password | Set once via Ansible | `argocd admin initial-password` |

To rotate the DB password:
```bash
# RDS rotates automatically with Secrets Manager rotation enabled
aws secretsmanager rotate-secret \
  --secret-id opsforge-staging/db-password
```

---

## Monitoring

```bash
# Port-forward Grafana (staging)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000  admin / your-password

# Port-forward ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open http://localhost:8080  admin / your-password

# Port-forward Argo Rollouts dashboard
kubectl port-forward -n argocd svc/argo-rollouts-dashboard 3100:3100
# Open http://localhost:3100
```
