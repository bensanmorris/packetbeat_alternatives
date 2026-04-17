#!/bin/bash
set -e

echo "=== Enabling L7 HTTP Visibility for Cilium (Persistent) ==="
echo ""

echo "Step 1: Checking Cilium status..."
if ! cilium status --wait --wait-duration=10s &> /dev/null; then
    echo "❌ Cilium is not ready. Please ensure Cilium is running."
    exit 1
fi
echo "✓ Cilium is running"

echo ""
echo "Step 2: Adding L7 annotations to deployment specs (persistent across restarts)..."

ANNOTATION='{"spec":{"template":{"metadata":{"annotations":{"policy.cilium.io/proxy-visibility":"<Ingress/80/TCP/HTTP>,<Egress/80/TCP/HTTP>"}}}}}'

# Get all deployments in demo namespace
DEPLOYMENTS=$(kubectl get deployments -n demo -o name 2>/dev/null || echo "")

if [ -z "$DEPLOYMENTS" ]; then
    echo "❌ No deployments found in demo namespace"
    exit 1
fi

echo "Found deployments:"
kubectl get deployments -n demo -o custom-columns=NAME:.metadata.name --no-headers

echo ""
echo "Patching deployments with L7 annotations..."

for deployment in $DEPLOYMENTS; do
    DEPLOY_NAME=$(echo $deployment | cut -d'/' -f2)
    echo "  - Patching $DEPLOY_NAME..."
    kubectl patch deployment "$DEPLOY_NAME" -n demo -p "$ANNOTATION"
done

echo "✓ L7 annotations added to deployment specs"

echo ""
echo "Step 3: Waiting for rollout to complete..."
echo "  (Pods will restart with L7 proxy enabled)"

# Wait for all deployments to roll out (compatible with older kubectl)
for deployment in $(kubectl get deployments -n demo -o name); do
    kubectl rollout status "$deployment" -n demo --timeout=180s
done

echo "✓ All deployments rolled out"

echo ""
echo "Step 4: Verifying annotations are present on new pods..."

# Check if annotations are on pods
ANNOTATED_PODS=$(kubectl get pods -n demo -o json | \
    jq -r '.items[] | select(.metadata.annotations["policy.cilium.io/proxy-visibility"] != null) | .metadata.name' | \
    wc -l)

TOTAL_PODS=$(kubectl get pods -n demo --no-headers | wc -l)

echo "  Annotated pods: $ANNOTATED_PODS / $TOTAL_PODS"

if [ "$ANNOTATED_PODS" -eq "$TOTAL_PODS" ]; then
    echo "✓ All pods have L7 annotations"
else
    echo "⚠️  Some pods may not have annotations yet (may need a few more seconds)"
fi

echo ""
echo "=== L7 Visibility Enabled ==="
echo ""
echo "Annotations are now part of the deployment specs."
echo "New pods will automatically have L7 visibility enabled."
echo ""
echo "Next steps:"
echo "  1. Wait 1-2 minutes for L7 proxy to initialize"
echo "  2. Verify with: ./testing/verify-l7-visibility.sh"
echo "  3. Check traffic: kubectl logs -n demo deployment/error-generator"
