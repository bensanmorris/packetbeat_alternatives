#!/bin/bash
set -e

echo "=== Enabling L7 HTTP Visibility for Cilium ==="
echo ""

echo "Step 1: Checking Cilium status..."
if ! cilium status &>/dev/null; then
    echo "❌ Cilium is not running. Please install Cilium first."
    exit 1
fi

echo "✅ Cilium is running"
echo ""

echo "Step 2: Enabling L7 visibility on all demo namespace pods..."
echo ""

# Enable L7 visibility for HTTP traffic (both ingress and egress on port 80)
kubectl annotate pod -n demo --all \
    policy.cilium.io/proxy-visibility="<Ingress/80/TCP/HTTP>,<Egress/80/TCP/HTTP>" \
    --overwrite

echo "✅ L7 annotations applied"
echo ""

echo "Step 3: Restarting deployments to pick up L7 proxy..."
echo ""

# Restart all deployments in demo namespace to pick up the new annotations
kubectl rollout restart deployment -n demo

echo "✅ Deployments restarted"
echo ""

echo "Step 4: Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod --all -n demo --timeout=120s

echo ""
echo "=== L7 Visibility Enabled ==="
echo ""

echo "Verify L7 is working:"
echo "  1. Generate some HTTP traffic:"
echo "     kubectl exec -n demo deployment/frontend -- curl http://backend/api/data"
echo ""
echo "  2. Check Hubble for L7 data:"
echo "     hubble observe --namespace demo --protocol http"
echo ""
echo "  3. You should see HTTP method, path, and status codes in the output"
echo ""

echo "To view L7 traffic continuously:"
echo "  hubble observe --namespace demo --protocol http --follow"
echo ""
