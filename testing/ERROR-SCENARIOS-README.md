# Error Scenario Testing

This extends the Cilium vs Packetbeat POC to test specific network error scenarios and evaluate which tool handles each better.

## What's Included

### 1. **error-generator.yaml**
Continuously generates various network errors:
- HTTP 4xx errors (400, 401, 403, 404)
- HTTP 5xx errors (500, 502, 503)
- Connection refused (wrong ports)
- DNS failures (non-existent domains)
- Timeouts (slow responses)
- Connection to non-existent IPs

### 2. **backend-error-service.yaml**
Enhanced backend that responds with specific HTTP status codes:
- `/status/400` - Returns 400 Bad Request
- `/status/500` - Returns 500 Internal Server Error
- `/delay/5` - Delays response by 5 seconds
- etc.

### 3. **network-policy-tests.yaml**
Creates restrictive network policies to test Cilium's policy visibility:
- `deny-all-ingress` - Blocks all incoming traffic to restricted pods
- `allow-from-frontend-only` - Only frontend can access backend
- `deny-external-egress` - Blocks external internet access

### 4. **policy-violator.yaml**
Pod that attempts connections that should be blocked by policies:
- Tries accessing restricted services
- Attempts cross-namespace access
- Tries external connections when egress is blocked

### 5. **deploy-error-scenarios.sh**
One-command deployment of all test scenarios

### 6. **analyze-error-scenarios.sh**
Analyzes collected data specifically for error scenarios and generates comparison report

## Quick Start (Post-Reboot / Fresh Start)

### Step 1: Check Cluster Status
```bash
cd ~/packetbeat_alternatives

# Check if Kind cluster is still running
sudo kind get clusters

# If cluster exists, check if it's healthy
kubectl get nodes
```

**Expected output if running:**
```
NAME                       STATUS   ROLES           AGE   VERSION
cilium-poc-control-plane   Ready    control-plane   1d    v1.27.3
cilium-poc-worker          Ready    <none>          1d    v1.27.3
cilium-poc-worker2         Ready    <none>          1d    v1.27.3
```

### Step 2a: If Cluster Running ✅

```bash
# Check Cilium status
cilium status

# Check existing pods
kubectl get pods -n demo
kubectl get pods -n monitoring

# Start Hubble port-forwarding
cilium hubble port-forward &

# Skip to Step 3!
```

### Step 2b: If Cluster NOT Running ❌

```bash
# Recreate the cluster (takes ~3 minutes)
cd setup
./02-create-cluster-rootful.sh

# Install Cilium
cd ../deploy
./cilium-install.sh

# Start Hubble port-forwarding
cilium hubble port-forward &

# Deploy Packetbeat
kubectl apply -f packetbeat-daemonset.yaml
kubectl apply -f packetbeat-config.yaml

# Deploy original test app
kubectl apply -f test-app.yaml

# Wait for everything to be ready
kubectl wait --for=condition=ready pod --all -n demo --timeout=120s
kubectl wait --for=condition=ready pod --all -n monitoring --timeout=120s
```

### Step 3: Deploy Error Scenarios

```bash

# Deploy all error scenarios (includes L7 enablement)
./testing/deploy-error-scenarios.sh
```

**Expected output:**
```
=== Deploying Error Scenario Tests ===

Step 1: Deploying enhanced backend with error responses...
deployment.apps/backend-error-capable created
...

Step 6: Enabling L7 HTTP visibility for Cilium...
  (This allows Cilium to capture HTTP methods, paths, and status codes)

Step 7: Restarting deployments to activate L7 proxy...

=== Error Scenarios Deployed ===
```

**Verify L7 is working:**
```bash
./testing/verify-l7-visibility.sh
```

### Step 4: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n demo

# Should see:
# - error-generator
# - policy-violator  
# - backend-error-capable
# - restricted-service
# - isolated-pod
# Plus original: frontend, backend, database
```

### Monitor Live

Open multiple terminal windows to watch different aspects:

**Terminal 1 - Watch Hubble capture policy violations:**
```bash
hubble observe --namespace demo --verdict DROPPED
```

**Terminal 2 - Watch error generator logs:**
```bash
kubectl logs -f -n demo deployment/error-generator
```

**Terminal 3 - Watch policy violator attempts:**
```bash
kubectl logs -f -n demo deployment/policy-violator
```

**Terminal 4 - Check network policies:**
```bash
kubectl get networkpolicies -n demo
```

### Let It Run

**Recommended duration:**
- **Minimum**: 10-15 minutes (proof of concept)
- **Better**: 30-60 minutes (decent data)
- **Best**: 2-4 hours (comprehensive results)

The error generators run continuously every 30 seconds.

### Collect Data

Let scenarios run for a chosen duration, then:

```bash
cd ~/packetbeat_alternatives/collection
./export-all.sh
```

This will take a few minutes depending on data volume.

### Analyze Results

```bash
cd ~/packetbeat_alternatives/analysis
./analyze-error-scenarios.sh
```

**Output:**
```
=== Analyzing Error Scenario Results ===

Report saved to: reports/error-scenarios-20260203-153000.txt
```

### Review Report

```bash
# View the report
cat reports/error-scenarios-*.txt | less

# Or open in your preferred editor
vim reports/error-scenarios-*.txt
```

## What Gets Tested

### ✅ HTTP Error Detection
- **Cilium**: Requires L7 visibility enabled
- **Packetbeat**: Always captures HTTP status codes
- **Winner**: TBD based on your data

### ✅ Network Policy Violations (Cilium's Killer Feature)
- **Cilium**: Shows which policy blocked, which pod, why
- **Packetbeat**: Just sees "connection failed" without context
- **Winner**: Cilium (by far)

### ✅ DNS Failures
- **Cilium**: Captures NXDOMAIN, SERVFAIL with pod context
- **Packetbeat**: Captures DNS responses with details
- **Winner**: Tie (both good)

### ✅ Connection Refused vs Timeout vs Dropped
- **Cilium**: Distinguishes by verdict and reason
- **Packetbeat**: Sees TCP flags but no policy context
- **Winner**: Cilium for Kubernetes environments

### ✅ Slow Responses / Timeouts
- **Cilium**: Flow-level timing only
- **Packetbeat**: Packet-level timing detail
- **Winner**: Packetbeat for deep timing analysis

## Quick Reference Checklist

```bash
# 1. Boot VM and navigate
cd ~/packetbeat_alternatives

# 2. Check cluster
kubectl get nodes

# 3. If needed, recreate cluster
./setup/02-create-cluster-rootful.sh
./deploy/cilium-install.sh
cilium hubble port-forward &
kubectl apply -f deploy/packetbeat-daemonset.yaml deploy/packetbeat-config.yaml deploy/test-app.yaml

# 4. Deploy error scenarios
./testing/deploy-error-scenarios.sh

# 5. Monitor (let run 30+ minutes)
kubectl logs -f -n demo deployment/error-generator

# 6. Collect
./collection/export-all.sh

# 7. Analyze
./analysis/analyze-error-scenarios.sh

# 8. Review
cat reports/error-scenarios-*.txt
```

## Time Estimates

| Step | Time |
|------|------|
| VM boot | 1-2 min |
| Cluster check | 30 sec |
| Cluster recreate (if needed) | 3-5 min |
| Cilium install | 2-3 min |
| Deploy error scenarios | 1-2 min |
| **Total cold start** | **8-13 min** |
| **Total if cluster running** | **2-3 min** |

## Key Insights You'll Get

1. **Can Cilium detect the errors you care about?**
   - Policy violations (Cilium only)
   - HTTP errors (both, if L7 enabled)
   - DNS failures (both)
   - Connection failures (both, but Cilium has context)

2. **Which provides better troubleshooting context?**
   - Cilium: Pod names, policies, Kubernetes labels
   - Packetbeat: IP addresses, detailed packet info

3. **Storage cost for error monitoring**
   - How much more data does Packetbeat capture?
   - Is the extra detail worth the cost?

## Expected Results

Based on similar tests, you should see:

**Network Policy Violations**:
- Cilium: Clear "POLICY_DENIED" with policy name
- Packetbeat: "Connection refused/timeout" (no context)
- **Cilium wins decisively**

**HTTP Errors**:
- Cilium: Visible if L7 enabled, with pod context
- Packetbeat: Always visible, more HTTP detail
- **Packetbeat has edge on detail**

**Storage**:
- Cilium: ~1-2GB for 24 hours with errors
- Packetbeat: ~50-100GB for 24 hours with errors
- **Cilium 50-100x more efficient**

## Troubleshooting

### Cluster won't start
```bash
# Check if old containers are stuck
sudo podman ps -a | grep cilium-poc

# Clean up and recreate
sudo kind delete cluster --name cilium-poc
./setup/02-create-cluster-rootful.sh
```

### Pods stuck in "Pending"
```bash
# Check node status
kubectl get nodes

# Check Cilium
cilium status

# If Cilium not ready, reinstall
./deploy/cilium-install.sh
```

### Error generator not creating errors
```bash
# Check if backend-errors service is running
kubectl get svc -n demo backend-errors

# Check error generator logs
kubectl logs -n demo deployment/error-generator

# If backend-errors doesn't exist
kubectl apply -f testing/backend-error-service.yaml
```

### No policy violations showing up
```bash
# Verify policies are created
kubectl get networkpolicies -n demo

# Check if Cilium is enforcing
cilium status

# Try manual test
kubectl exec -n demo deployment/policy-violator -- curl -v http://restricted-service:80/
```

### Hubble connection refused
```bash
# Restart port-forward
pkill -f "hubble.*port-forward"
cilium hubble port-forward &

# Test
hubble observe --last 10
```

### Hubble not showing L7 data
```bash
# Check if L7 visibility is enabled
./testing/verify-l7-visibility.sh

# If not enabled, run:
./testing/enable-l7-visibility.sh

# Or manually enable L7 visibility for HTTP
kubectl annotate pod -n demo --all policy.cilium.io/proxy-visibility="<Ingress/80/TCP/HTTP>,<Egress/80/TCP/HTTP>" --overwrite

# Restart pods to pick up annotation
kubectl rollout restart deployment -n demo

# Wait for pods to be ready
kubectl wait --for=condition=ready pod --all -n demo --timeout=120s

# Verify it's working
hubble observe --namespace demo --protocol http --last 10
```

## Advanced: Custom Error Scenarios

Edit `error-scenarios` ConfigMap to add your own tests:

```bash
kubectl edit configmap error-scenarios -n demo

# Add your test, for example:
# curl -X POST http://backend:80/custom-endpoint
```

## Cleanup

```bash
# Remove error scenarios but keep original test app
kubectl delete -f testing/error-generator.yaml
kubectl delete -f testing/backend-error-service.yaml
kubectl delete -f testing/network-policy-tests.yaml
kubectl delete -f testing/policy-violator.yaml

# Or remove everything
./cleanup/cleanup-all.sh
```

## Next Steps

1. Run for 30-60 minutes minimum
2. Collect data: `./collection/export-all.sh`
3. Analyze: `./analysis/analyze-error-scenarios.sh`
4. Review the report to determine which tool better meets our needs
5. Make decision: Hubble primary + Packetbeat on-demand, or all Packetbeat?

## Report Output

The analysis script produces a detailed report showing:
- HTTP error detection comparison
- Network policy violation visibility (Cilium's strength)
- DNS failure detection
- Connection failure type distinction
- Scenario-specific findings
- Recommendations by error type

The report will clearly show which tool is better for each scenario in your specific environment.

## Pro Tips

1. **Save terminal commands for next time:**
```bash
cat > ~/start-error-tests.sh <<'EOF'
#!/bin/bash
cd ~/packetbeat_alternatives
kubectl get nodes || ./setup/02-create-cluster-rootful.sh
cilium hubble port-forward &
./testing/deploy-error-scenarios.sh
kubectl logs -f -n demo deployment/error-generator
EOF
chmod +x ~/start-error-tests.sh
```

2. **Check everything before walking away:**
```bash
kubectl get pods -n demo | grep -E "error-generator|policy-violator|restricted"
# All should show "Running"
```

3. **Watch live in browser:** Access Hubble UI at http://localhost:12000 (after running `cilium hubble ui`)
