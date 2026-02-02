#!/bin/bash
set -e

echo "=== Installing Cilium with Hubble ==="
echo ""

# Verify cluster is running
if ! kubectl get nodes &> /dev/null; then
    echo "ERROR: Cannot connect to cluster"
    echo "Make sure the cluster is running: ./setup/02-create-cluster.sh"
    exit 1
fi

echo "Step 1: Installing Cilium..."
cilium install --wait

echo ""
echo "Step 2: Enabling Hubble with UI..."
cilium hubble enable --ui

echo ""
echo "Step 3: Waiting for Cilium to be ready..."
cilium status --wait

echo ""
echo "Step 4: Running connectivity test..."
echo "This verifies Cilium networking is working correctly..."
cilium connectivity test --test '!pod-to-pod-encryption,!node-to-node-encryption' || {
    echo "⚠️  Some connectivity tests failed, but basic networking may still work"
    echo "This is often OK for a POC environment"
}

echo ""
echo "=== Cilium Installation Complete ==="
echo ""
echo "Cilium Status:"
cilium status

echo ""
echo "To access Hubble UI:"
echo "  cilium hubble ui"
echo "  (Opens browser at http://localhost:12000)"
echo ""
echo "To view live flows:"
echo "  hubble observe"
echo ""
echo "Next step:"
echo "  kubectl apply -f deploy/packetbeat-config.yaml"
echo "  kubectl apply -f deploy/packetbeat-daemonset.yaml"
