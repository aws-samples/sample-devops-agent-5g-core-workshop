# AWS DevOps Agent + 5G Core — Workshop Guide

## What You'll Build

A fully instrumented 5G Core network on EKS, then use AWS DevOps Agent to investigate cross-layer incidents — from Kubernetes pods to security groups to CloudTrail audit logs — in under 3 minutes per scenario.

**Time:** ~45 min setup + 30 min demo (4 scenarios)

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  EKS Cluster (v1.30) — devops-agent-demo                         │
│  Nodes: system (t3.medium×2) + app (t3.medium×2, max=3)         │
│                                                                  │
│  ┌─────────────────────────── demo-5g ─────────────────────────┐ │
│  │                                                              │ │
│  │              ┌─────────┐                                     │ │
│  │  ┌──────────│   NRF   │──────────┐                          │ │
│  │  │          │ (Redis) │          │                          │ │
│  │  │Nnrf      └────┬────┘     Nnrf │                          │ │
│  │  │               │               │                          │ │
│  │  ▼          N1/N2 ▼          N11  ▼                          │ │
│  │ ┌───┐     ┌─────────┐    ┌─────────┐    ┌─────────┐        │ │
│  │ │UPF│     │   AMF   │───▶│   SMF   │    │   PCF   │        │ │
│  │ └───┘     └─────────┘    └────┬────┘    └─────────┘        │ │
│  │                                │N4                           │ │
│  │               ┌────────────────▼───┐                        │ │
│  │               │  UE Simulator      │                        │ │
│  │               │  (load generator)  │                        │ │
│  │               └────────────────────┘                        │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  Observability: Container Insights (enhanced) + Control Plane Logs │
│  Scaling: HPA (AMF) + Cluster Autoscaler                          │
│  Alarms: 6 CloudWatch alarms (scenario-aligned)                   │
└────────────────────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
   ElastiCache Redis     SQS (orders queue)
```

## Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| AWS CLI | v2 | `aws --version` |
| Terraform | ≥ 1.5 | `terraform version` |
| kubectl | ≥ 1.28 | `kubectl version --client` |
| helm | ≥ 3.12 | `helm version` |
| jq | any | `jq --version` |

**AWS Account:** Isengard (or any account with admin access). Cost: ~$5/hour while running.

## Setup (One-Time)

### 1. Clone and configure

```bash
git clone <REPO_URL>
cd devops-agent-eks-demo

# Make scripts executable
chmod +x deploy.sh verify.sh scripts-5g/*.sh

cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set region (default: us-east-1)
```

### 2. Deploy infrastructure (~10 min)

```bash
terraform init
terraform apply
```

This creates: VPC, EKS cluster, ElastiCache Redis, SQS queue, Container Insights, ALB Controller, CloudWatch Alarms.

### 3. Deploy 5G Core (~2 min)

```bash
cd ..
./deploy.sh
```

This configures kubectl, deploys Cluster Autoscaler, and deploys all 5G network functions with correct Redis/SQS endpoints.

### 4. Verify health (~30s)

```bash
./verify.sh
```

All checks should pass before proceeding.

### 5. Create DevOps Agent Space (Console — ~5 min)

This step is manual (learning objective: understand Agent Space setup).

1. Open **AWS Console → DevOps Agent → Create Agent Space**
   - Name: `5g-core-demo`
   - Let it auto-create the IAM role

2. **Capabilities → Cloud → Primary Source**
   - Select your account
   - Validate connection (green check)

3. **EKS Console → Cluster → Access tab → Create access entry**
   - IAM Principal ARN: copy from Agent Space capabilities page
   - Access Policy: `AmazonAIOpsAssistantPolicy`
   - Scope: **Cluster**

4. **Verify** — back in Agent Space, ask:
   > "List all pods in the demo-5g namespace"

   You should see NRF, AMF, SMF, UPF, PCF, UE-simulator pods.

5. **Update Terraform** (optional, for alarm permissions):
   ```bash
   cd terraform/
   # Edit terraform.tfvars — set devops_agent_role_arn
   terraform apply
   ```

### 6. Verify Topology

In Agent Space → **Topology** tab, confirm you see:
- EKS cluster with node groups
- All K8s deployments/pods/services in demo-5g
- ElastiCache cluster
- SQS queue

---

## Running the Demo

### Before each scenario

1. Open **CloudWatch → Alarms** in a browser tab (filter: `5G-Core-*`)
2. Open **Agent Space** in another tab
3. Confirm all alarms are in OK state: `./verify.sh`

### Scenario flow (same for all 4)

```
inject → wait (30s-3min) → alarm fires → paste prompt → agent investigates → discuss → restore
```

---

## Scenarios

See individual scenario guides:
- [Scenario 1: Who Changed the Security Group?](scenario-1.md)
- [Scenario 2: Pods Won't Schedule During Busy Hour](scenario-2.md)
- [Scenario 3: The Deployment That Broke the AMF](scenario-3.md)
- [Scenario 4: The Scaling Storm](scenario-4.md)

---

## Cleanup

```bash
kubectl delete namespace demo-5g
cd terraform/ && terraform destroy
```

**Cost note:** The cluster costs ~$5/hour. Destroy when not in use.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `deploy.sh` fails on terraform output | Run `terraform apply` first |
| Pods stuck in Pending | Check node capacity: `kubectl describe nodes` |
| NRF can't reach Redis | Check SG rules: `aws ec2 describe-security-groups --group-ids <sg-id>` |
| Agent can't see pods | Verify EKS access entry exists with correct role ARN |
| Alarms don't fire | Wait 2-3 min — CloudWatch needs datapoints |
| Scenario restore fails | Re-run restore script; if stuck, redeploy: `./deploy.sh` |
