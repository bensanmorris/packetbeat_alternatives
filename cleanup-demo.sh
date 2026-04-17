#!/bin/bash
set -e

echo "=== Cleaning Up Demo Namespace ==="
echo ""

echo "Step 1: Deleting all resources in demo namespace..."
kubectl delete namespace demo --ignore-not-found=true

echo ""
echo "Step 2: Waiting for namespace deletion..."
while kubectl get namespace demo &> /dev/null; do
    echo -n "."
    sleep 2
done
echo ""

echo ""
echo "Step 3: Recreating demo namespace..."
kubectl create namespace demo

echo ""
echo "=== Demo Namespace Reset Complete ==="
echo ""
echo "Next steps:"
echo "  ./testing/deploy-error-scenarios.sh"
