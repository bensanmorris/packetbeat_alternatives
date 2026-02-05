#!/bin/bash
set -e

echo "=== Deploying Error Scenario Tests ==="
echo ""

# Check if we're in the right directory
if [ ! -f "deploy/test-app.yaml" ]; then
    echo "ERROR: Please run this from the cilium-packetbeat-poc directory"
    exit 1
fi

echo "Step 1: Deploying enhanced backend with error responses..."
kubectl apply -f testing/backend-error-service.yaml

echo ""
echo "Step 2: Deploying error generator..."
kubectl apply -f testing/error-generator.yaml

echo ""
echo "Step 3: Deploying network policy tests..."
kubectl apply -f testing/network-policy-tests.yaml

echo ""
echo "Step 4: Deploying policy violator..."
kubectl apply -f testing/policy-violator.yaml

echo ""
echo "Step 5: Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=error-generator -n demo --timeout=60s || echo "  ⚠️  error-generator not ready yet"
kubectl wait --for=condition=ready pod -l app=backend-error-capable -n demo --timeout=60s || echo "  ⚠️  backend-error-capable not ready yet"
kubectl wait --for=condition=ready pod -l app=policy-violator -n demo --timeout=60s || echo "  ⚠️  policy-violator not ready yet"
kubectl wait --for=condition=ready pod -l app=restricted-service -n demo --timeout=60s || echo "  ⚠️  restricted-service not ready yet"

echo ""
echo "Step 6: Enabling L7 HTTP visibility for Cilium..."
echo "  (This allows Cilium to capture HTTP methods, paths, and status codes)"
kubectl annotate pod -n demo --all \
    policy.cilium.io/proxy-visibility="<Ingress/80/TCP/HTTP>,<Egress/80/TCP/HTTP>" \
    --overwrite

echo ""
echo "Step 7: Restarting deployments to activate L7 proxy..."
kubectl rollout restart deployment -n demo

echo ""
echo "Step 8: Waiting for deployments to be ready with L7 enabled..."
kubectl wait --for=condition=ready pod --all -n demo --timeout=120s

echo ""
echo "=== Error Scenarios Deployed ==="
echo ""
echo "Active error generators:"
echo "  1. error-generator      - HTTP errors, timeouts, DNS failures"
echo "  2. policy-violator      - Network policy violations"
echo "  3. restricted-service   - Target for policy tests"
echo "  4. backend-errors       - Responds with various HTTP status codes"
echo ""
echo "View logs:"
echo "  kubectl logs -f -n demo deployment/error-generator"
echo "  kubectl logs -f -n demo deployment/policy-violator"
echo ""
echo "Monitor with Hubble:"
echo "  hubble observe --namespace demo --verdict DROPPED"
echo "  hubble observe --namespace demo --protocol http"
echo "  hubble observe --namespace demo --from-pod error-generator"
echo ""
echo "Check Cilium network policies:"
echo "  kubectl get networkpolicies -n demo"
echo "  cilium endpoint list"
echo ""
echo "Let these run for 10-30 minutes, then collect data:"
echo "  cd collection && ./export-all.sh"
