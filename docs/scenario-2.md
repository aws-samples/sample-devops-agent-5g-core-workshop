# Scenario 2: Pods Won't Schedule During Busy Hour

## Story

Peak busy hour traffic arrives. The AMF HPA tries to scale up to handle subscriber registrations, but the underlying Auto Scaling Group is capped at its current node count. New AMF pods are stuck in Pending — subscribers experience registration timeouts.

## Failure Chain

```
UE load spike → HPA requests more AMF replicas → scheduler can't place them
→ FailedScheduling: Insufficient cpu → nodes at capacity → ASG at maxSize
→ Cluster Autoscaler blocked → subscriber registrations queue and timeout
```

## Alarms Expected

| Alarm | Trigger |
|-------|---------|
| 5G-Core-AMF-Replicas-Unavailable | Desired > Available |
| 5G-Core-Cluster-Node-Capacity-Saturated | Node CPU ≥ 80% |
| 5G-Core-AMF-HPA-Scaling-Storm | Desired replicas > 6 (side effect) |

## Run

### Inject (~2-3 min to manifest)

```bash
./scripts-5g/scenario-2-asg-ceiling.sh inject
```

Wait 2-3 minutes for HPA to scale, pods to go Pending, and alarms to fire.

### Observe

```bash
# Pending pods
kubectl get pods -n demo-5g | grep Pending

# Events showing FailedScheduling
kubectl get events -n demo-5g --sort-by='.lastTimestamp' | grep FailedScheduling

# Node utilization
kubectl top nodes
```

### Agent Prompt

> AMF pods in demo-5g namespace are stuck in Pending state. We're seeing subscriber registration timeouts during peak busy hour. Investigate why AMF cannot scale.

### Expected Agent Investigation Path

1. Lists pods → sees multiple AMF pods in Pending state
2. Describes a Pending pod → sees `FailedScheduling: Insufficient cpu`
3. Checks node allocatable vs. requested → nodes at capacity (17/17 pods or similar)
4. Identifies the Auto Scaling Group → sees `maxSize` = current count
5. May check CloudTrail for who modified the ASG (if the cap was recently changed)
6. Recommends: increase ASG maxSize, consider larger instance types, or set PriorityClass

### Key Demo Talking Points

- Agent traced from **application symptom** (Pending pods) through **Kubernetes scheduler** to **AWS infrastructure** (ASG limits)
- Understood the ENI/IP limits on t3.medium (17 pods per node)
- Connected Cluster Autoscaler behavior to ASG configuration
- This is a common real-world issue: someone caps ASG for cost control, forgets during traffic spike

### Restore

```bash
./scripts-5g/scenario-2-asg-ceiling.sh restore
```

ASG max restored, extra nodes launch, Pending pods schedule. Alarms clear in 2-3 min.

## Timing

- Inject to visible Pending: ~2-3 min
- Agent investigation: ~3-5 min
- Total scenario: ~8 min
