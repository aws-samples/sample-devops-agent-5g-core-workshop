#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# deploy.sh — Post-Terraform K8s deployment for 5G Core Demo
#
# Run AFTER: terraform apply (which creates VPC, EKS, Redis, SQS, Container
#            Insights, ALB Controller)
# Run BEFORE: creating the DevOps Agent Space in the console
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "═══════════════════════════════════════════════════════════════"
echo "  5G Core Demo — Deploy"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# --- Step 1: Get Terraform outputs -------------------------------------------
echo "▸ Reading Terraform outputs..."
cd "${TF_DIR}"

CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null) || {
  echo "ERROR: Cannot read terraform outputs. Run 'terraform apply' first."; exit 1
}
REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")
REDIS_HOST=$(terraform output -raw redis_endpoint)
SQS_URL=$(terraform output -raw sqs_queue_url)
CA_ROLE=$(terraform output -raw cluster_autoscaler_role_arn)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "  Cluster:  ${CLUSTER_NAME}"
echo "  Region:   ${REGION}"
echo "  Account:  ${ACCOUNT_ID}"
echo "  Redis:    ${REDIS_HOST}"
echo ""

# --- Step 2: Configure kubectl ------------------------------------------------
echo "▸ Configuring kubectl..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}" --alias "${CLUSTER_NAME}" >/dev/null
echo "  ✓ kubeconfig updated"
echo ""

# --- Step 3: Deploy Cluster Autoscaler ----------------------------------------
echo "▸ Deploying Cluster Autoscaler..."
cd "${SCRIPT_DIR}"

# Patch CA role ARN into manifest
sed "s|REPLACE_WITH_CA_ROLE_ARN|${CA_ROLE}|g" k8s-5g/cluster-autoscaler.yaml | kubectl apply -f - >/dev/null
kubectl rollout status deployment/cluster-autoscaler -n kube-system --timeout=60s >/dev/null 2>&1 || true
echo "  ✓ Cluster Autoscaler running"
echo ""

# --- Step 4: Deploy 5G Core NFs -----------------------------------------------
echo "▸ Deploying 5G Core network functions..."

# Patch namespace configmap with real endpoints
PATCHED_NS=$(sed \
  -e "s|REPLACE_WITH_REDIS_ENDPOINT|${REDIS_HOST}|g" \
  -e "s|REPLACE_WITH_SQS_URL|${SQS_URL}|g" \
  k8s-5g/namespace.yaml)

echo "${PATCHED_NS}" | kubectl apply -f - >/dev/null

# Deploy NFs in dependency order: NRF first (service registry), then others
kubectl apply -f k8s-5g/nrf.yaml >/dev/null
echo "  ✓ NRF (service registry)"

kubectl rollout status deployment/nrf -n demo-5g --timeout=120s >/dev/null 2>&1

kubectl apply -f k8s-5g/pcf.yaml >/dev/null
kubectl apply -f k8s-5g/upf.yaml >/dev/null
kubectl apply -f k8s-5g/smf.yaml >/dev/null
echo "  ✓ PCF, UPF, SMF"

kubectl apply -f k8s-5g/amf.yaml >/dev/null
echo "  ✓ AMF (with HPA)"

kubectl apply -f k8s-5g/ue-simulator.yaml >/dev/null
echo "  ✓ UE Simulator (load generator)"

kubectl apply -f k8s-5g/ingress.yaml >/dev/null
echo "  ✓ ALB Ingress"

echo ""

# --- Step 5: Wait for all pods ------------------------------------------------
echo "▸ Waiting for pods to be ready..."
kubectl wait --for=condition=ready pods --all -n demo-5g --timeout=180s >/dev/null 2>&1
echo "  ✓ All 5G NFs running"
echo ""

# --- Done ---------------------------------------------------------------------
echo "═══════════════════════════════════════════════════════════════"
echo "  ✓ Deployment complete!"
echo ""
echo "  Next steps:"
echo "    1. Run ./verify.sh to confirm health"
echo "    2. Create DevOps Agent Space in the AWS Console"
echo "    3. Add EKS access entry for the agent role"
echo "    4. Run scenarios: ./scripts-5g/scenario-1-sg-change.sh inject"
echo "═══════════════════════════════════════════════════════════════"
