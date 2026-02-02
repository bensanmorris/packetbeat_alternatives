#!/bin/bash
set -e

echo "=== Verifying Setup ==="
echo ""

# Check Kind cluster
echo "1. Checking Kind cluster..."
if kind get clusters | grep -q "cilium-poc"; then
    echo "   ✓ Cluster 'cilium-poc' exists"
else
    echo "   ✗ Cluster 'cilium-poc' not found"
    echo "   Run: ./setup/02-create-cluster.sh"
    exit 1
fi

# Check kubectl context
echo "2. Checking kubectl context..."
CURRENT_CONTEXT=$(kubectl config current-context)
if [ "$CURRENT_CONTEXT" = "kind-cilium-poc" ]; then
    echo "   ✓ kubectl configured for cilium-poc"
else
    echo "   ⚠️  Current context: $CURRENT_CONTEXT"
    echo "   Switching to kind-cilium-poc..."
    kubectl config use-context kind-cilium-poc
fi

# Check nodes
echo "3. Checking cluster nodes..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
echo "   Found $NODE_COUNT nodes:"
kubectl get nodes --no-headers | awk '{print "     - " $1 " (" $2 ")"}'

# Check if nodes are ready
NOT_READY=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l || true)
if [ "$NOT_READY" -gt 0 ]; then
    echo "   ⚠️  Some nodes are not ready (this is expected before Cilium installation)"
else
    echo "   ✓ All nodes are ready"
fi

# Check Podman containers
echo "4. Checking Podman containers..."
CONTAINER_COUNT=$(podman ps --filter "label=io.x-k8s.kind.cluster=cilium-poc" --format "{{.Names}}" | wc -l)
echo "   Found $CONTAINER_COUNT Kind containers:"
podman ps --filter "label=io.x-k8s.kind.cluster=cilium-poc" --format "     - {{.Names}}"

# Check required tools
echo "5. Checking required tools..."
TOOLS_OK=1
for tool in kubectl cilium hubble jq; do
    if command -v $tool &> /dev/null; then
        echo "   ✓ $tool"
    else
        echo "   ✗ $tool not found"
        TOOLS_OK=0
    fi
done

if [ $TOOLS_OK -eq 0 ]; then
    echo ""
    echo "Some tools are missing. Run: ./setup/01-install-tools.sh"
    exit 1
fi

echo ""
echo "=== Verification Complete ==="
echo ""
echo "Your cluster is ready for Cilium and Packetbeat installation."
echo ""
echo "Next steps:"
echo "  1. Install Cilium: ./deploy/cilium-install.sh"
echo "  2. Deploy Packetbeat: kubectl apply -f deploy/packetbeat-config.yaml"
echo "                        kubectl apply -f deploy/packetbeat-daemonset.yaml"
echo "  3. Deploy test app: kubectl apply -f deploy/test-app.yaml"
