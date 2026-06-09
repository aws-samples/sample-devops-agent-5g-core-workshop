variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "devops-agent-demo"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "devops_agent_role_arn" {
  description = "IAM role ARN from your DevOps Agent Space (found in Capabilities > Cloud > Primary Source > Edit)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "devops-agent-eks-demo"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}
