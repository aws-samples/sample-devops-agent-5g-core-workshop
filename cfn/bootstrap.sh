#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Standalone bootstrap for running on any Amazon Linux 2023 EC2
#
# Use this if you're NOT using the CloudFormation template (cfn/workshop-infra.yaml)
# and want to manually provision on your own EC2 instance.
#
# The CFN template inlines this logic in UserData with CFN signal handling.
# This standalone version is for self-paced users or Cloud9/EC2 environments.
#
# This script:
#   1. Installs all required tools (terraform, kubectl, helm, jq, git)
#   2. Clones the workshop repository
#   3. Runs terraform apply to build infrastructure (~15 min)
#   4. Runs deploy.sh to deploy 5G NFs
#   5. Runs verify.sh to confirm health
#
# Progress is written to /opt/workshop/status.txt and logged to
# /var/log/workshop-setup.log
# =============================================================================
set -euo pipefail

# --- Configuration (passed via CFN UserData environment) ----------------------
REPO_URL="${REPO_URL:-https://github.com/aws-samples/sample-devops-agent-5g-core-workshop.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CFN_SIGNAL_URL="${CFN_SIGNAL_URL:-}"
WORKSHOP_DIR="/opt/workshop"
STATUS_FILE="${WORKSHOP_DIR}/status.txt"
LOG_FILE="/var/log/workshop-setup.log"

# --- Helpers ------------------------------------------------------------------
update_status() {
  echo "$1" | tee "${STATUS_FILE}"
  echo "[$(date '+%H:%M:%S')] $1" >> "${LOG_FILE}"
}

signal_success() {
  if [[ -n "${CFN_SIGNAL_URL}" ]]; then
    curl -X PUT -H 'Content-Type:' \
      --data-binary '{"Status":"SUCCESS","Reason":"Workshop environment ready","UniqueId":"bootstrap","Data":"complete"}' \
      "${CFN_SIGNAL_URL}"
  fi
}

signal_failure() {
  local reason="${1:-Setup failed — check /var/log/workshop-setup.log}"
  if [[ -n "${CFN_SIGNAL_URL}" ]]; then
    curl -X PUT -H 'Content-Type:' \
      --data-binary "{\"Status\":\"FAILURE\",\"Reason\":\"${reason}\",\"UniqueId\":\"bootstrap\",\"Data\":\"failed\"}" \
      "${CFN_SIGNAL_URL}"
  fi
}

# Trap any failure and signal CFN
trap 'signal_failure "Bootstrap failed at line $LINENO — check /var/log/workshop-setup.log"' ERR

# --- Setup --------------------------------------------------------------------
mkdir -p "${WORKSHOP_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

update_status "[1/5] Installing tools..."

# AWS CLI (already on AL2023)
aws --version

# Terraform
TERRAFORM_VERSION="1.9.8"
curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip
unzip -o /tmp/terraform.zip -d /usr/local/bin/
rm /tmp/terraform.zip
terraform version

# kubectl
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl
kubectl version --client

# Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# jq (already on AL2023, but ensure)
yum install -y jq git 2>/dev/null || true

update_status "[2/5] Cloning repository..."

cd "${WORKSHOP_DIR}"
git clone --branch "${REPO_BRANCH}" "${REPO_URL}" repo
cd repo

update_status "[3/5] Running Terraform — building EKS, VPC, Redis (~15 min)..."

cd terraform
cat > terraform.tfvars <<EOF
region       = "${AWS_REGION}"
cluster_name = "devops-agent-demo"
EOF

terraform init -no-color
terraform apply -auto-approve -no-color

cd ..

update_status "[4/5] Deploying 5G Core network functions..."

./deploy.sh

update_status "[5/5] Verifying environment..."

./verify.sh

# Save verify output for participants to view
./verify.sh > "${WORKSHOP_DIR}/verify-output.txt" 2>&1 || true

update_status "✅ READY — environment deployed successfully! Run ./verify.sh to see status."

# --- Signal CFN ---------------------------------------------------------------
signal_success

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Bootstrap complete at $(date)"
echo "  Workshop directory: ${WORKSHOP_DIR}/repo"
echo "═══════════════════════════════════════════════════════════════"
