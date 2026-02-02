#!/bin/bash
set -e

echo "=== Creating Kind Cluster with Podman (Rootful Mode) ==="
echo ""
echo "Note: This uses rootful Podman (with sudo) to avoid systemd delegation issues."
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
if ! sudo podman info &> /dev/null; then
    echo "ERROR: Podman is not working correctly"
    exit 1
fi

# Check cgroup version using grep method
if sudo podman info 2>/dev/null | grep -q "cgroupVersion: v2"; then
    CGROUP_VERSION="v2"
elif sudo podman info 2>/dev/null | grep -q "cgroup version: 2"; then
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

# Create cluster using rootful Podman (with sudo)
echo ""
echo "Creating Kind cluster 'cilium-poc'..."
echo "This may take several minutes..."
echo ""
echo "Note: Running with sudo to use rootful Podman"
echo ""

cd "$(dirname "$0")/../deploy"

# Find kind binary location
KIND_PATH=$(which kind)
if [ -z "$KIND_PATH" ]; then
    echo "ERROR: kind command not found"
    echo "Please run: ./setup/01-install-tools.sh"
    exit 1
fi

echo "Using kind from: $KIND_PATH"
echo ""

# Run kind with sudo to use rootful Podman
sudo -E KIND_EXPERIMENTAL_PROVIDER=podman "$KIND_PATH" create cluster --config kind-config.yaml --name cilium-poc

echo ""
echo "✓ Cluster created successfully"
echo ""

# Fix kubectl context permissions for regular user
echo "Fixing kubectl permissions..."

# Get the actual kubeconfig path
KUBECONFIG_PATH="${HOME}/.kube/config"

# Always get fresh kubeconfig from the newly created cluster
echo "Getting kubeconfig from cluster..."
sudo mkdir -p "${HOME}/.kube"
sudo -E KIND_EXPERIMENTAL_PROVIDER=podman "$KIND_PATH" get kubeconfig --name cilium-poc > "${KUBECONFIG_PATH}.tmp"

# Move it to the right place and fix permissions
mv "${KUBECONFIG_PATH}.tmp" "${KUBECONFIG_PATH}"
chmod 600 "${KUBECONFIG_PATH}"

# Ensure user owns their .kube directory
chown -R $(id -u):$(id -g) "${HOME}/.kube"

echo "✓ kubectl context configured"

# Verify cluster
echo ""
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
echo ""
echo "Note: Since we used rootful Podman, you'll need to use 'sudo podman'"
echo "commands to interact with the Kind containers directly."
