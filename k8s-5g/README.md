# 5G Core Demo — Deployment Guide

## Overview

Same EKS infrastructure as the retail demo. Only the app layer changes — namespace `demo-5g` with 5G network function stubs that speak telco language.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     5G Core (demo-5g namespace)                   │
│                                                                  │
│                          ┌─────────┐                             │
│              ┌───────────│   NRF   │───────────┐                 │
│              │           │ (Redis) │           │                 │
│              │           └────┬────┘           │                 │
│              │Nnrf        Nnrf│          Nnrf  │                 │
│              │                │                │                 │
│  ┌─────┐ N1/N2  ┌───────┐  N11  ┌───────┐   │    ┌───────┐    │
│  │ UE  │───────▶│  AMF  │──────▶│  SMF  │   │    │  PCF  │    │
│  │(load)│        │       │       │       │   │    │       │    │
│  └─────┘        └───────┘       └───┬───┘   │    └───────┘    │
│                                      │N4     │                  │
│                                  ┌───▼───┐   │                  │
│                                  │  UPF  │───┘                  │
│                                  └───────┘                      │
│                                                                  │
│  Nnrf = Service discovery (all NFs → NRF via Redis)             │
│  N11  = Session management (AMF → SMF)                          │
│  N4   = Session rules (SMF → UPF)                               │
└──────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- EKS cluster `devops-agent-demo` already running (from retail demo)
- ElastiCache Redis already deployed
- ALB Ingress Controller already installed
- Cluster Autoscaler already running
- Container Insights already enabled

## Deploy

```bash
# Apply all 5G manifests
kubectl apply -f k8s-5g/namespace.yaml
kubectl apply -f k8s-5g/nrf.yaml
kubectl apply -f k8s-5g/pcf.yaml
kubectl apply -f k8s-5g/upf.yaml
kubectl apply -f k8s-5g/smf.yaml
kubectl apply -f k8s-5g/amf.yaml
kubectl apply -f k8s-5g/ue-simulator.yaml
kubectl apply -f k8s-5g/ingress.yaml

# Verify all NFs are running
kubectl get pods -n demo-5g

# Check NRF can reach Redis
kubectl logs -l app=nrf -n demo-5g --tail=5

# Check AMF registered with NRF
kubectl logs -l app=amf -n demo-5g --tail=5
```

## Verify

```bash
# NRF health (should show redis=connected)
kubectl exec -n demo-5g deploy/nrf -- python -c "
import urllib.request; print(urllib.request.urlopen('http://localhost:8080/health').read().decode())"

# Send a test UE registration through AMF
kubectl exec -n demo-5g deploy/amf -- python -c "
import urllib.request, json
req = urllib.request.Request('http://localhost:8080/namf-comm/v1/ue-registrations',
    data=json.dumps({'supi':'imsi-001010000000001'}).encode(),
    headers={'Content-Type':'application/json'}, method='POST')
print(urllib.request.urlopen(req).read().decode())"
```

## Scenarios

### Scenario 1: "Who changed the Security Group?"
```bash
./scripts-5g/scenario-1-sg-change.sh inject

# Agent prompt:
# "The 5G core NFs in demo-5g namespace are failing to establish PDU sessions.
#  AMF logs show NRF discovery failures starting about 1 minute ago. Investigate."

./scripts-5g/scenario-1-sg-change.sh restore
```

### Scenario 2: "Pods won't schedule during busy hour"
```bash
./scripts-5g/scenario-2-asg-ceiling.sh inject

# Agent prompt:
# "AMF pods in demo-5g namespace are stuck in Pending state. We're seeing
#  subscriber registration timeouts during peak busy hour. Investigate why
#  AMF cannot scale."

./scripts-5g/scenario-2-asg-ceiling.sh restore
```

### Scenario 3: "The deployment that broke the AMF"
```bash
./scripts-5g/scenario-3-bad-deploy.sh inject

# Agent prompt:
# "The AMF deployment in demo-5g namespace is failing. All new pods are in
#  ImagePullBackOff. Subscriber registrations are completely down. Investigate
#  what changed."

./scripts-5g/scenario-3-bad-deploy.sh restore
```

### Scenario 4: "The scaling storm during busy hour"
```bash
./scripts-5g/scenario-4-scaling-storm.sh inject

# Agent prompt:
# "The AMF HPA in demo-5g is rapidly scaling pods up and down. We're seeing
#  intermittent subscriber registration failures during busy hour. Investigate
#  the scaling behavior."

./scripts-5g/scenario-4-scaling-storm.sh restore
```

## What the Agent Sees

The key differentiator is the **log language**. When DevOps Agent investigates, it sees:

- NRF: `"ERROR: NRF Redis health check failed: Connection refused"`
- AMF: `"ERROR: UE registration failed - NRF unavailable | SUPI=imsi-001010000000042"`
- SMF: `"INFO: PDU session established | PDU-SESSION-ID=pdu-00012 | SUPI=imsi-... | DNN=internet | S-NSSAI=sst:1/sd:000001"`
- UPF: `"INFO: PDR rule installed | PDU-SESSION-ID=pdu-00012 | TEID=1012 | action=FORWARD"`
- PCF: `"INFO: Policy decision created | policy-id=pd-000003 | 5QI=9 | AMBR=100/200 Mbps"`

A telco engineer watching the demo immediately recognizes their world: SUPIs, PDU sessions, TEIDs, 5QI, DNNs, S-NSSAI.

## Cleanup

```bash
kubectl delete namespace demo-5g
```
