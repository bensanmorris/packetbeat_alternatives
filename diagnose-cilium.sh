#!/bin/bash

echo "=== Cilium Installation Diagnostics ==="
echo ""

echo "1. Checking node status..."
kubectl get nodes -o wide
echo ""

echo "2. Checking if nodes are ready..."
kubectl get nodes | grep -v NAME | awk '{print $1, $2}'
echo ""

echo "3. Checking pod status in kube-system..."
kubectl get pods -n kube-system -o wide
echo ""

echo "4. Checking Cilium pod details (looking for scheduling issues)..."
kubectl get pods -n kube-system -l k8s-app=cilium -o yaml | grep -A 5 "conditions:" | head -20
echo ""

echo "5. Describing a Cilium pod (checking for errors)..."
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -1)
if [ -n "$CILIUM_POD" ]; then
    kubectl describe -n kube-system "$CILIUM_POD" | tail -30
else
    echo "No Cilium pods found"
fi
echo ""

echo "6. Checking for taint issues on nodes..."
kubectl get nodes -o json | jq -r '.items[] | .metadata.name + ": " + (.spec.taints // [] | tostring)'
echo ""

echo "7. Checking Kind cluster container status..."
sudo podman ps -a | grep cilium-poc
echo ""

echo "8. Checking if control-plane node has NoSchedule taint..."
kubectl describe node | grep -A 3 "Taints:"
echo ""

echo "=== Common Issues and Fixes ==="
echo ""
echo "If nodes show 'NotReady':"
echo "  - Wait 1-2 minutes, nodes may still be initializing"
echo "  - Check: kubectl describe nodes"
echo ""
echo "If control-plane is tainted (NoSchedule):"
echo "  - This is normal for Kind, Cilium should still install"
echo ""
echo "If all nodes Ready but pods still Pending:"
echo "  - Try: kubectl delete pods -n kube-system -l k8s-app=cilium"
echo "  - Or: cilium uninstall && ./deploy/cilium-install.sh"
echo ""
