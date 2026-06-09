# =============================================================================
# ElastiCache Redis — Cross-layer failure demo (SG scenario)
# =============================================================================

resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_name}-redis-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for Redis - DevOps Agent demo"

  # Inbound from EKS pod CIDR (private subnets)
  ingress {
    description = "Redis from EKS pods"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-redis"
    # Tag for easy identification during demo
    Demo = "scenario-1-sg-change"
  })
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.cluster_name}-redis"
  subnet_ids = module.vpc.elasticache_subnets
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.cluster_name}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t3.micro" # Small for demo
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  tags = var.tags
}
