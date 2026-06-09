output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_security_group_id" {
  description = "SG to modify for Scenario 1 (revoke port 6379 rule)"
  value       = aws_security_group.redis.id
}

output "sqs_queue_url" {
  value = aws_sqs_queue.orders.url
}

output "app_nodegroup_asg_lookup" {
  description = "Run this to get ASG name for Scenario 2"
  value       = "aws eks describe-nodegroup --cluster-name ${module.eks.cluster_name} --nodegroup-name app --query 'nodegroup.resources.autoScalingGroups[0].name' --output text --region ${var.region}"
}

output "vpc_private_subnet_cidrs" {
  description = "Pod CIDRs — needed for SG rule restoration in Scenario 1"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "next_steps" {
  value = <<-EOT

    ┌─────────────────────────────────────────────────────────────┐
    │ NEXT STEPS                                                   │
    │                                                              │
    │ 1. Configure kubectl:                                        │
    │    aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}
    │                                                              │
    │ 2. Update k8s/app.yaml with real endpoints:                  │
    │    redis-host: (see redis_endpoint output above)             │
    │    sqs-queue-url: (see sqs_queue_url output above)           │
    │                                                              │
    │ 3. Deploy app:                                               │
    │    kubectl apply -f ../k8s/namespace.yaml                    │
    │    kubectl apply -f ../k8s/app.yaml                          │
    │    kubectl apply -f ../k8s/cluster-autoscaler.yaml           │
    │                                                              │
    │ 4. Create DevOps Agent Space via console                     │
    │    Then add EKS access entry with the agent role             │
    │                                                              │
    │ 5. Run scenarios:                                            │
    │    ./scripts/scenario-1-sg-change.sh inject                  │
    └─────────────────────────────────────────────────────────────┘
  EOT
}
