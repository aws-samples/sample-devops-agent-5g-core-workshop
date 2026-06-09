# =============================================================================
# VPC — 3 AZs, public + private subnets, NAT gateway
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # ElastiCache subnet group
  elasticache_subnets = ["10.0.51.0/24", "10.0.52.0/24", "10.0.53.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true # Cost optimization for demo
  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS requires these tags for subnet discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  tags = var.tags
}
