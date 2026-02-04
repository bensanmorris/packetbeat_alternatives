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

## Quick Start

### Deploy Error Scenarios

```bash
# Deploy all scenarios
./testing/deploy-error-scenarios.sh
```

### Monitor Live

```bash
# Watch Hubble capture policy violations
hubble observe --namespace demo --verdict DROPPED

# Watch error generator logs
kubectl logs -f -n demo deployment/error-generator

# Watch policy violator attempts
kubectl logs -f -n demo deployment/policy-violator

# Check network policies
kubectl get networkpolicies -n demo
```

### Collect Data

Let scenarios run for at least 10-30 minutes, then:

```bash
cd collection
./export-all.sh
```

### Analyze Results

```bash
cd ../analysis
./analyze-error-scenarios.sh
```

## What Gets Tested

### ✅ HTTP Error Detection
- **Cilium**: Requires L7 visibility enabled
- **Packetbeat**: Always captures HTTP status codes
- **Winner**: TBD based on the data

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

## Key Insights You'll Get

1. **Can Cilium detect the errors we care about?**
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

### Error generator not creating errors
```bash
# Check if backend-errors service is running
kubectl get svc -n demo backend-errors

# Check error generator logs
kubectl logs -n demo deployment/error-generator
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

### Hubble not showing L7 data
```bash
# Enable L7 visibility for HTTP
kubectl annotate pod -n demo --all policy.cilium.io/proxy-visibility="<Ingress/80/TCP/HTTP>"

# Restart pods to pick up annotation
kubectl rollout restart deployment -n demo
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
4. Review the report to determine which tool better meets your needs
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
