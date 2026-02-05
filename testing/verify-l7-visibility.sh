#!/bin/bash
set -e

echo "=== Verifying L7 HTTP Visibility ==="
echo ""

echo "Step 1: Checking pod annotations..."
echo ""
kubectl get pods -n demo -o custom-columns=NAME:.metadata.name,L7-ANNOTATION:.metadata.annotations.'policy\.cilium\.io/proxy-visibility' 2>/dev/null || {
    echo "❌ No L7 annotations found on pods"
    echo ""
    echo "To enable L7 visibility, run:"
    echo "  ./testing/enable-l7-visibility.sh"
    exit 1
}

echo ""
echo "Step 2: Generating test HTTP traffic..."
echo ""

# Generate some HTTP traffic
echo "Testing frontend -> backend connection..."
kubectl exec -n demo deployment/frontend -- curl -s http://backend/api/data > /dev/null && echo "✅ Frontend to backend: Success" || echo "❌ Frontend to backend: Failed"

echo "Testing error scenario (404)..."
kubectl exec -n demo deployment/frontend -- curl -s http://backend/api/notfound > /dev/null && echo "✅ 404 request sent" || echo "✅ 404 request sent (expected to fail)"

echo ""
echo "Step 3: Checking for L7 data in Hubble (last 20 flows)..."
echo ""

HUBBLE_OUTPUT=$(hubble observe --namespace demo --protocol http --last 20 2>&1)

if echo "$HUBBLE_OUTPUT" | grep -q "GET\|POST\|http-request\|http-response"; then
    echo "✅ L7 HTTP data detected in Hubble!"
    echo ""
    echo "Sample L7 flows:"
    echo "$HUBBLE_OUTPUT" | head -10
    echo ""
    echo "=== L7 Visibility is Working! ==="
    echo ""
    echo "You can monitor L7 traffic with:"
    echo "  hubble observe --namespace demo --protocol http --follow"
    echo ""
    echo "To see HTTP status codes:"
    echo "  hubble observe --namespace demo --http-status 200"
    echo "  hubble observe --namespace demo --http-status 404"
    echo "  hubble observe --namespace demo --http-status 500"
else
    echo "❌ No L7 HTTP data found in Hubble"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check if Cilium proxy is enabled:"
    echo "   cilium status | grep -i proxy"
    echo ""
    echo "2. Check pod annotations:"
    echo "   kubectl get pods -n demo -o yaml | grep -A5 annotations"
    echo ""
    echo "3. Check Cilium agent logs:"
    echo "   kubectl logs -n kube-system -l k8s-app=cilium --tail=50 | grep -i proxy"
    echo ""
    echo "4. Restart pods to pick up annotations:"
    echo "   kubectl rollout restart deployment -n demo"
    echo ""
    echo "Raw Hubble output:"
    echo "$HUBBLE_OUTPUT"
fi

echo ""
