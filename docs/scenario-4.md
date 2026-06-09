# Scenario 4: The Scaling Storm

## Story

An SRE set aggressive HPA parameters — ultra-low CPU target (15%) and zero stabilization window — to "ensure fast scaling." During busy hour, this creates a feedback loop: HPA scales up aggressively, new pods drag average CPU down, HPA scales back, load returns, cycle repeats. Each scaling event disrupts connection pools to Redis.

## Failure Chain

```
HPA target=15% + stabilizationWindow=0s → aggressive scale-up
→ new pods join → average CPU drops → HPA scales down
→ remaining pods overloaded → HPA scales up again
→ each cycle disrupts NRF Redis connections (420x spike per cycle)
→ intermittent PDU session failures during oscillation
```

## Alarms Expected

| Alarm | Trigger |
|-------|---------|
| 5G-Core-AMF-HPA-Scaling-Storm | Desired replicas > 6 |
| 5G-Core-Cluster-Node-Capacity-Saturated | Node CPU ≥ 80% (during up-cycles) |

## Run

### Inject (~2-3 min to see oscillation)

```bash
./scripts-5g/scenario-4-scaling-storm.sh inject
```

Wait 2-3 minutes for HPA oscillation to become visible. You'll see replica count swing wildly (e.g., 2→9→2→7).

### Observe

```bash
# Watch HPA oscillate in real time
kubectl get hpa amf -n demo-5g -w

# Events stream showing scaling
kubectl get events -n demo-5g --sort-by='.lastTimestamp' --watch

# Replica history
kubectl describe hpa amf -n demo-5g | tail -20
```

### Agent Prompt

> The AMF HPA in demo-5g is rapidly scaling pods up and down. We're seeing intermittent subscriber registration failures during busy hour. Investigate the scaling behavior.

### Expected Agent Investigation Path

1. Checks HPA status → sees rapid replica count changes (oscillation pattern)
2. Inspects HPA spec → identifies:
   - CPU target: 15% (too aggressive)
   - stabilizationWindowSeconds: 0 (no cooldown)
3. Correlates with metrics → shows CPU oscillating as pods join/leave
4. May identify Redis connection spike (NRF reconnection storm per cycle)
5. May check Container Insights → correlates pod scaling events with latency spikes
6. Recommends:
   - Raise CPU target to 60-70%
   - Add stabilizationWindowSeconds (300s recommended)
   - Consider custom metrics instead of CPU for network workloads

### Key Demo Talking Points

- This is the **hardest** scenario — it's a configuration mistake, not a broken component
- Agent understood the HPA feedback loop dynamics and explained the oscillation mechanism
- Connected infrastructure scaling to application impact (connection pool churn)
- Found the NRF connection pooling bug: each scale event creates 420x Redis connection spike
- Real-world: this exact scenario happens when teams set aggressive HPA targets without stabilization

### Restore

```bash
./scripts-5g/scenario-4-scaling-storm.sh restore
```

Restores original HPA parameters (70% target, 300s stabilization). Oscillation stops within one cooldown period.

## Timing

- Inject to visible oscillation: ~2-3 min
- Agent investigation: ~6-8 min (longest scenario)
- Total scenario: ~12 min

## Advanced Follow-Up

After the agent explains the issue, try asking:

> "What would prevent this in the future? Suggest guardrails."

The agent typically recommends:
- OPA/Kyverno policy to enforce minimum stabilizationWindow
- Alerting on HPA replica count rate-of-change
- Custom metrics (connection count per pod) instead of raw CPU
