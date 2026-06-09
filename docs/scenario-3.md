# Scenario 3: The Deployment That Broke the AMF

## Story

A developer pushes a new AMF image tag that doesn't exist in the registry. The deployment rolls forward, new pods fail with ImagePullBackOff, and the old pods are terminated by the rollout. The entire AMF fleet is down — subscribers can't register.

## Failure Chain

```
kubectl set image → AMF deployment updated → new pods created
→ ImagePullBackOff (tag doesn't exist) → old pods terminated
→ AMF completely unavailable → all UE registrations fail
```

## Alarms Expected

| Alarm | Trigger |
|-------|---------|
| 5G-Core-AMF-Replicas-Unavailable | Available replicas = 0 |

## Run

### Inject (~30s to manifest)

```bash
./scripts-5g/scenario-3-bad-deploy.sh inject
```

Pods go to ImagePullBackOff almost immediately.

### Observe

```bash
# Pods in error state
kubectl get pods -n demo-5g -l app=amf

# Describe shows image pull error
kubectl describe pod -n demo-5g -l app=amf | grep -A3 "Events"
```

### Agent Prompt

> The AMF deployment in demo-5g namespace is failing. All new pods are in ImagePullBackOff. Subscriber registrations are completely down. Investigate what changed.

### Expected Agent Investigation Path

1. Lists pods → sees AMF pods in ImagePullBackOff
2. Describes pod → sees invalid image tag (e.g., `amf:v2.1.0-broken`)
3. Checks deployment history → sees recent change to image spec
4. Queries EKS audit logs (via CloudWatch Logs Insights) → finds:
   - Exact `kubectl set image` command
   - User who ran it (IAM principal)
   - Source IP
   - kubectl version string
   - `fieldManager: kubectl-set`
5. Recommends: rollback to previous revision, add image validation in CI/CD

### Key Demo Talking Points

- Agent used **EKS audit logs** to find the exact deployment change — not just "it broke" but WHO broke it
- Distinguished between ImagePullBackOff (tag doesn't exist) vs CrashLoopBackOff (app crashes)
- This is the "3am page" scenario — agent gives you the answer in 3 min instead of 30 min of `kubectl describe` + CloudTrail digging
- If GitHub is connected, agent can trace to the exact commit

### Restore

```bash
./scripts-5g/scenario-3-bad-deploy.sh restore
```

Rolls back to working image. Pods healthy within 30s.

## Timing

- Inject to visible failure: ~30s
- Agent investigation: ~3-4 min
- Total scenario: ~5 min
