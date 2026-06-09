# =============================================================================
# DevOps Agent — Manual Console Setup
# =============================================================================
# The DevOps Agent Space is created manually via the AWS Console for demo impact.
#
# After creating the Agent Space, grab the role ARN from:
#   Agent Space → Capabilities → Cloud → Primary Source → Edit → Role ARN
#
# Then set it in terraform.tfvars:
#   devops_agent_role_arn = "arn:aws:iam::123456789012:role/AWSDevOpsAgent-xxxxx"
#
# And run: terraform apply
# This will create the EKS access entry so the agent can query the cluster.
# =============================================================================
