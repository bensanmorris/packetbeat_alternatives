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
echo "=== Enabling L7 HTTP Visibility ==="
echo ""

# Enable L7 visibility automatically
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/enable-l7-visibility.sh" ]; then
    "$SCRIPT_DIR/enable-l7-visibility.sh"
else
    echo "⚠️  L7 visibility script not found"
    echo "Run manually: ./testing/enable-l7-visibility.sh"
fi

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  1. Verify L7: ./testing/verify-l7-visibility.sh"
echo "  2. Monitor traffic: kubectl logs -f -n demo deployment/error-generator"
echo "  3. Let run 30-60 minutes to accumulate ~5000 flows"
echo "  4. Collect data: ./collection/export-all.sh"
