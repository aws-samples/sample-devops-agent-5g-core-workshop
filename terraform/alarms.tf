# =============================================================================
# CloudWatch Alarms — 5G Core Network Monitoring
# Simulates a telco NOC alarm panel. Each alarm maps to a scenario.
#
# These alarms rely on Enhanced Container Insights (pod-level metrics).
# Metric reference: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-enhanced-EKS.html
# =============================================================================

# =============================================================================
# Top-Level Service Impact Alarm (fires for ANY 5G core issue)
# This is the "big red light" in the NOC — subscriber sessions impacted.
#
# Uses service_number_of_running_pods for the NRF service. When NRF pods fail
# their readiness probe (Redis unreachable → /health returns 503), they are
# removed from the Service endpoints and this count drops.
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "nf_not_ready" {
  alarm_name          = "5G-Core-NF-Not-Ready"
  alarm_description   = "5G NRF service has fewer than 2 ready pods — service registry degraded. All inter-NF discovery depends on NRF backed by Redis. When NRF readiness fails, AMF/SMF cannot discover peers and PDU session establishment fails network-wide."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "service_number_of_running_pods"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Minimum"
  threshold           = 2
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = var.cluster_name
    Namespace   = "demo-5g"
    Service     = "nrf"
  }

  tags = merge(var.tags, { Demo = "top-level-noc-alarm", NF = "NRF" })
}

# =============================================================================
# Scenario 1: SG Change — NRF loses Redis connectivity
#
# What happens: SG inbound rule revoked → NRF can't reach Redis → readiness
# probe returns 503 → pods go NotReady → all NF discovery requests get 503.
#
# Alarm: ElastiCache CurrConnections drops to 0 (definitive signal that
# Redis is unreachable from pods). The top-level NF-Not-Ready alarm also fires.
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "nrf_redis_disconnected" {
  alarm_name          = "5G-Core-NRF-Redis-Disconnected"
  alarm_description   = "Zero new Redis connections in the past minute — NRF pods cannot reach the service registry backend. NRF uses short-lived connections for each operation; healthy baseline is ~40-50/min. Likely cause: Security Group change blocking port 6379 from EKS pod subnets. Check SG ${aws_security_group.redis.id} inbound rules."
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "NewConnections"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "breaching"

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }

  tags = merge(var.tags, { Demo = "scenario-1-sg-change", NF = "NRF" })
}

# =============================================================================
# Scenario 2: ASG Ceiling — AMF can't scale during busy hour
#
# What happens: ASG max capped → AMF scaled to 8 replicas → some pods Pending
# because no nodes available → FailedScheduling events.
#
# Alarm strategy:
#   Primary: status_replicas_unavailable > 0 for AMF (pods exist but aren't ready)
#   Secondary: Node CPU saturation (all nodes full, nowhere to put pods)
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "amf_replicas_unavailable" {
  alarm_name          = "5G-Core-AMF-Replicas-Unavailable"
  alarm_description   = "AMF deployment has unavailable replicas — pods likely stuck in Pending state. During busy hour (mass UE attach), AMF must scale horizontally. If pods cannot be scheduled, check node group capacity and ASG MaxSize."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "status_replicas_unavailable"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    Namespace   = "demo-5g"
    PodName     = "amf"
  }

  tags = merge(var.tags, { Demo = "scenario-2-asg-ceiling", NF = "AMF" })
}

resource "aws_cloudwatch_metric_alarm" "cluster_node_saturated" {
  alarm_name          = "5G-Core-Cluster-Node-Capacity-Saturated"
  alarm_description   = "EKS app nodes at high CPU utilization with pending scheduling requests. ASG may be at MaxSize preventing scale-out. Check: aws autoscaling describe-auto-scaling-groups for MaxSize vs DesiredCapacity."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
  }

  tags = merge(var.tags, { Demo = "scenario-2-asg-ceiling" })
}

# =============================================================================
# Scenario 3: Bad Deployment — AMF image pull failure
#
# What happens: kubectl set image → non-existent tag → ImagePullBackOff →
# new pods never start → unavailable replicas increases.
#
# Alarm: Uses the same AMF-Replicas-Unavailable alarm from Scenario 2.
# Both scenarios produce unavailable replicas (Pending vs ImagePullBackOff)
# — the DevOps Agent differentiates the root cause.
# =============================================================================

# =============================================================================
# Scenario 4: Scaling Storm — AMF HPA oscillation
#
# What happens: HPA target set to 5% with 0s stabilization → pods scale
# 2→9→2→7 repeatedly → connection churn on Redis → intermittent failures.
#
# Alarm: replicas_desired spikes above 3 (HPA over-reacting).
# Using replicas_desired rather than available because during oscillation
# pods may scale up before they all become ready.
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "amf_scaling_oscillation" {
  alarm_name          = "5G-Core-AMF-HPA-Scaling-Storm"
  alarm_description   = "AMF desired replica count spiking abnormally (>6) — HPA may be over-scaling. Normal baseline is 2 replicas. Rapid scale-up followed by scale-down indicates misconfigured HPA target or stabilization window. Check: kubectl describe hpa amf-hpa -n demo-5g."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "replicas_desired"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Maximum"
  threshold           = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    Namespace   = "demo-5g"
    PodName     = "amf"
  }

  tags = merge(var.tags, { Demo = "scenario-4-scaling-storm", NF = "AMF" })
}

# =============================================================================
# Redis Health — Baseline monitoring (supports all scenarios)
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  alarm_name          = "5G-Core-Redis-Engine-CPU-High"
  alarm_description   = "ElastiCache Redis engine CPU elevated — NRF service registry backend under stress. May indicate connection storm from NF pod churn or legitimate traffic increase."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }

  tags = merge(var.tags, { NF = "NRF" })
}
