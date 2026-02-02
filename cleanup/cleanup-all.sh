#!/bin/bash
set -e

echo "=== Full POC Cleanup ==="
echo ""
echo "This will:"
echo "  • Delete the Kind cluster"
echo "  • Remove all collected data"
echo "  • Clean up Podman containers"
echo ""

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Step 1: Deleting Kind cluster..."
kind delete cluster --name cilium-poc 2>&1 || echo "Cluster may already be deleted"

echo ""
echo "Step 2: Cleaning up Podman containers..."
# Remove any lingering containers
podman ps -a --filter "label=io.x-k8s.kind.cluster=cilium-poc" --format "{{.Names}}" | \
    xargs -r podman rm -f 2>&1 || true

echo ""
echo "Step 3: Removing data directories..."
rm -rf data/
rm -rf reports/

echo ""
echo "Step 4: Cleaning up Podman system..."
podman system prune -f

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "The POC environment has been completely removed."
echo ""
echo "To start over:"
echo "  ./setup/02-create-cluster.sh"
