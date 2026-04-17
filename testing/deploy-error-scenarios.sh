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
echo "  kubectl get ciliumnetworkpolicies -n demo"
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Traffic is being generated every 30 seconds."
echo ""
echo "Note: L7 HTTP visibility is disabled by default as it can cause"
echo "connectivity issues. The test works fine with L3/L4 flow data."
echo ""
echo "To enable L7 (optional, advanced):"
echo "  kubectl apply -f testing/cilium-l7-policy.yaml"
echo "  ./testing/enable-l7-visibility.sh"
echo ""
echo "Next steps:"
echo "  1. Verify traffic: kubectl logs -f -n demo deployment/error-generator"
echo "  2. Let run 30-60 minutes to accumulate ~5000 flows"
echo "  3. Collect data: ./collection/export-all.sh"
echo "  4. Analyze: ./testing/analyze-error-scenarios.sh"
