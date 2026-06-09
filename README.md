# AWS DevOps Agent × 5G Core — Cross-Layer Investigation Demo

Demonstrate [AWS DevOps Agent](https://docs.aws.amazon.com/devops-agent/) investigating cross-layer incidents on EKS — from Kubernetes pod failures to AWS infrastructure changes to CloudTrail audit logs — in under 3 minutes per scenario.

## What's Inside

A simulated 5G Core network (AMF, SMF, UPF, NRF, PCF) running on EKS with ElastiCache Redis as the service registry backend. Four pre-built failure scenarios inject real infrastructure problems that the DevOps Agent investigates end-to-end.

| Scenario | Failure Type | Agent Finds | Time |
|----------|-------------|-------------|------|
| 1. SG Change | Security Group blocks Redis | CloudTrail: who/when/IP | ~2 min |
| 2. ASG Ceiling | Node group can't scale | ASG maxSize, node saturation | ~4 min |
| 3. Bad Deploy | Invalid image tag pushed | EKS audit log: exact kubectl command | ~3 min |
| 4. Scaling Storm | HPA oscillation | Feedback loop, connection pooling bug | ~8 min |

## Quick Start

```bash
# 1. Infrastructure (~10 min)
cd terraform/
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

# 2. Application (~2 min)
cd ..
./deploy.sh

# 3. Verify
./verify.sh

# 4. Create DevOps Agent Space (console — see docs/)

# 5. Run scenarios
./scripts-5g/scenario-1-sg-change.sh inject
# → paste agent prompt → watch investigation → restore
./scripts-5g/scenario-1-sg-change.sh restore
```

## Repository Structure

```
├── terraform/              Infrastructure (VPC, EKS, Redis, SQS, Alarms)
├── k8s-5g/                 5G Core manifests (NRF, AMF, SMF, UPF, PCF)
├── scripts-5g/             Scenario inject/restore scripts
├── docs/                   Workshop guide + per-scenario walkthroughs
├── deploy.sh               Post-Terraform K8s deployment
└── verify.sh               Health check
```

## Prerequisites

- AWS account (Isengard or standard — admin access needed)
- Terraform ≥ 1.5, AWS CLI v2, kubectl, helm, jq
- ~$5/hour while running

## Documentation

- **[Introduction](docs/introduction.md)** — 5G Core primer, DevOps Agent overview, telco value proposition
- **[Workshop Guide](docs/workshop-guide.md)** — Full setup instructions
- **[Scenario 1](docs/scenario-1.md)** — Security Group change
- **[Scenario 2](docs/scenario-2.md)** — ASG capacity ceiling
- **[Scenario 3](docs/scenario-3.md)** — Bad deployment
- **[Scenario 4](docs/scenario-4.md)** — HPA scaling storm

## Why 5G?

The 5G network functions use proper 3GPP vocabulary (SUPI, PDU sessions, S-NSSAI, DNN, 5QI) so the demo resonates with telco engineers. The underlying failure modes are universal EKS patterns — the same scenarios apply to any microservices architecture.

## Cleanup

```bash
kubectl delete namespace demo-5g
cd terraform/ && terraform destroy
```
