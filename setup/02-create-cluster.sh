#!/bin/bash
set -e

echo "=== Creating Kind Cluster with Podman ==="
echo ""

# Set Podman as provider
export KIND_EXPERIMENTAL_PROVIDER=podman

# Add to bashrc if not already there
if ! grep -q "KIND_EXPERIMENTAL_PROVIDER" ~/.bashrc; then
    echo 'export KIND_EXPERIMENTAL_PROVIDER=podman' >> ~/.bashrc
    echo "Added KIND_EXPERIMENTAL_PROVIDER to ~/.bashrc"
fi

# Verify Podman is working
echo "Verifying Podman..."
if ! podman info &> /dev/null; then
    echo "ERROR: Podman is not working correctly"
    exit 1
fi

# Check cgroup version using grep method
if podman info 2>/dev/null | grep -q "cgroupVersion: v2"; then
    CGROUP_VERSION="v2"
elif podman info 2>/dev/null | grep -q "cgroup version: 2"; then
    CGROUP_VERSION="v2"
else
    CGROUP_VERSION="v1"
fi
if [ "$CGROUP_VERSION" != "v2" ]; then
    echo "ERROR: cgroup v2 is required but found: $CGROUP_VERSION"
    echo "Please run: sudo ./setup/00-prerequisites.sh"
    exit 1
fi
echo "✓ Podman configured with cgroup v2"

# Create cluster
echo ""
echo "Creating Kind cluster 'cilium-poc'..."
echo "This may take several minutes..."
echo ""

cd "$(dirname "$0")/../deploy"
kind create cluster --config kind-config.yaml --name cilium-poc

echo ""
echo "✓ Cluster created successfully"
echo ""

# Verify cluster
echo "Verifying cluster..."
kubectl cluster-info --context kind-cilium-poc

echo ""
echo "Checking cluster nodes..."
kubectl get nodes

echo ""
echo "=== Cluster Creation Complete ==="
echo ""
echo "Next step:"
echo "  ./setup/03-verify-setup.sh"
