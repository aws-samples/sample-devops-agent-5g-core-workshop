# =============================================================================
# EKS Cluster + Node Groups
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable EKS API authentication mode (required for DevOps Agent access entries)
  authentication_mode = "API_AND_CONFIG_MAP"

  # Control plane logging — needed for DevOps Agent investigations
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Cluster endpoint access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Allow control plane to reach metrics-server addon on port 10251
  node_security_group_additional_rules = {
    metrics_server_ingress = {
      description                   = "Cluster API to metrics-server"
      protocol                      = "tcp"
      from_port                     = 10251
      to_port                       = 10251
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # EKS Addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    # Required for HPA CPU-based scaling (Scenario 4)
    metrics-server = {
      most_recent = true
    }
  }

  # --------------------------------------------------------------------------
  # Node Groups
  # --------------------------------------------------------------------------
  eks_managed_node_groups = {
    # System node group — for cluster add-ons, monitoring, ingress
    system = {
      name           = "system"
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = {
        role = "system"
      }

      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]

      iam_role_additional_policies = {
        CloudWatchAgent = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }
    }

    # App node group — for demo workloads (intentionally constrained for scenarios)
    app = {
      name           = "app"
      instance_types = ["t3.medium"] # 2 vCPU, 4GB — tight enough for OOMKill demos
      min_size       = 2
      max_size       = 3 # Intentionally low for ASG ceiling scenario
      desired_size   = 2

      labels = {
        role = "app"
      }

      iam_role_additional_policies = {
        CloudWatchAgent = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }
    }
  }

  # --------------------------------------------------------------------------
  # Access Entries — DevOps Agent + current user
  # --------------------------------------------------------------------------
  access_entries = merge(
    # DevOps Agent access (only if role ARN is provided)
    var.devops_agent_role_arn != "" ? {
      devops_agent = {
        principal_arn = var.devops_agent_role_arn
        policy_associations = {
          aiops = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonAIOpsAssistantPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    } : {},
    # Current user — cluster admin
    # When running on EC2 with instance profile, caller_identity returns an
    # assumed-role ARN (arn:aws:sts::ACCT:assumed-role/ROLE_NAME/INSTANCE_ID).
    # EKS access entries require the IAM role ARN format.
    {
      admin = {
        principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${element(split("/", data.aws_caller_identity.current.arn), 1)}"
        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    }
  )

  tags = var.tags
}
