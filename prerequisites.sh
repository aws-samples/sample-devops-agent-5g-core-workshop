#!/usr/bin/env bash
# =============================================================================
# prerequisites.sh — Check that all required tools are installed
#
# Run this BEFORE starting the workshop. It checks for required CLI tools
# and prints install instructions for anything missing.
# =============================================================================

PASS="✓"
FAIL="✗"
missing=0

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  5G Core Demo — Prerequisites Check"
echo "═══════════════════════════════════════════════════════════════"
echo ""

check_tool() {
  local name="$1"
  local cmd="$2"
  local install_mac="$3"
  local install_linux="$4"
  local min_version="$5"

  if command -v "$cmd" >/dev/null 2>&1; then
    version=$("$cmd" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+[\.0-9]*' | head -1)
    echo "  ${PASS} ${name} (${version:-installed})"
  else
    echo "  ${FAIL} ${name} — not found"
    if [[ "$(uname)" == "Darwin" ]]; then
      echo "    Install: ${install_mac}"
    else
      echo "    Install: ${install_linux}"
    fi
    missing=$((missing + 1))
  fi
}

echo "▸ Required tools"
echo ""

check_tool "AWS CLI" "aws" \
  "brew install awscli" \
  "curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o awscliv2.zip && unzip awscliv2.zip && sudo ./aws/install"

check_tool "Terraform" "terraform" \
  "brew install terraform" \
  "sudo apt-get install -y terraform  (or: https://developer.hashicorp.com/terraform/install)"

check_tool "kubectl" "kubectl" \
  "brew install kubectl" \
  "curl -LO \"https://dl.k8s.io/release/\$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && sudo install kubectl /usr/local/bin/"

check_tool "Helm" "helm" \
  "brew install helm" \
  "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

check_tool "jq" "jq" \
  "brew install jq" \
  "sudo apt-get install -y jq"

echo ""

# Check AWS credentials
echo "▸ AWS credentials"
echo ""
if aws sts get-caller-identity >/dev/null 2>&1; then
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  IDENTITY=$(aws sts get-caller-identity --query Arn --output text)
  echo "  ${PASS} Authenticated"
  echo "    Account:  ${ACCOUNT}"
  echo "    Identity: ${IDENTITY}"
else
  echo "  ${FAIL} Not authenticated"
  echo "    Run: aws configure  (or set AWS_PROFILE / AWS_ACCESS_KEY_ID)"
  missing=$((missing + 1))
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [[ "${missing}" -eq 0 ]]; then
  echo "  ${PASS} All prerequisites met — ready to start!"
  echo ""
  echo "  Next: cd terraform && cp terraform.tfvars.example terraform.tfvars"
  echo "        terraform init && terraform apply"
else
  echo "  ${FAIL} ${missing} item(s) missing — install and re-run"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""
exit "${missing}"
