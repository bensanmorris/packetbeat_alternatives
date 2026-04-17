#!/bin/bash
set -e

echo "=== Cleaning Up Kind Cluster ==="
echo ""

CLUSTER_NAME="cilium-poc"

echo "Checking for existing cluster..."
if sudo kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Found cluster '$CLUSTER_NAME', deleting..."
    sudo kind delete cluster --name "$CLUSTER_NAME"
    echo "✓ Cluster deleted"
else
    echo "No cluster named '$CLUSTER_NAME' found"
fi

echo ""
echo "Cleaning up any orphaned containers..."
sudo podman ps -a --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" --format "{{.ID}}" | xargs -r sudo podman rm -f 2>/dev/null || true

echo ""
echo "Cleaning up any orphaned networks..."
sudo podman network ls --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" --format "{{.Name}}" | xargs -r sudo podman network rm 2>/dev/null || true

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "You can now run: ./setup/02-create-cluster-rootful.sh"
