#!/bin/bash
set -e

echo "=== Installing Required Tools ==="
echo ""

# Determine installation directory
INSTALL_DIR="${HOME}/.local/bin"
USE_SUDO=0

if [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
elif [ "$EUID" -eq 0 ]; then
    INSTALL_DIR="/usr/local/bin"
    USE_SUDO=0
else
    echo "Installing to user directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> ~/.bashrc
        export PATH="$PATH:$INSTALL_DIR"
        echo "Added $INSTALL_DIR to PATH in ~/.bashrc"
    fi
fi

echo "Installation directory: $INSTALL_DIR"
echo ""

# Install Kind
echo "Installing Kind..."
KIND_VERSION="v0.20.0"
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
chmod +x ./kind
if [ "$USE_SUDO" -eq 1 ]; then
    sudo mv ./kind "$INSTALL_DIR/kind"
else
    mv ./kind "$INSTALL_DIR/kind"
fi
echo "✓ Kind ${KIND_VERSION} installed"

# Install kubectl
echo "Installing kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
if [ "$USE_SUDO" -eq 1 ]; then
    sudo mv kubectl "$INSTALL_DIR/kubectl"
else
    mv kubectl "$INSTALL_DIR/kubectl"
fi
echo "✓ kubectl ${KUBECTL_VERSION} installed"

# Install Cilium CLI
echo "Installing Cilium CLI..."
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz"
tar xzvf cilium-linux-amd64.tar.gz cilium
chmod +x cilium
if [ "$USE_SUDO" -eq 1 ]; then
    sudo mv cilium "$INSTALL_DIR/cilium"
else
    mv cilium "$INSTALL_DIR/cilium"
fi
rm cilium-linux-amd64.tar.gz
echo "✓ Cilium CLI ${CILIUM_CLI_VERSION} installed"

# Install Hubble CLI
echo "Installing Hubble CLI..."
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all "https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-amd64.tar.gz"
tar xzvf hubble-linux-amd64.tar.gz hubble
chmod +x hubble
if [ "$USE_SUDO" -eq 1 ]; then
    sudo mv hubble "$INSTALL_DIR/hubble"
else
    mv hubble "$INSTALL_DIR/hubble"
fi
rm hubble-linux-amd64.tar.gz
echo "✓ Hubble CLI ${HUBBLE_VERSION} installed"

# Install jq (for JSON processing)
echo "Installing jq..."
if command -v dnf &> /dev/null; then
    if [ "$EUID" -eq 0 ]; then
        dnf install -y jq
    else
        sudo dnf install -y jq
    fi
    echo "✓ jq installed"
else
    echo "⚠️  Could not install jq automatically. Please install manually: sudo dnf install -y jq"
fi

echo ""
echo "=== Tool Installation Complete ==="
echo ""
echo "Verifying installations..."
echo ""

# Verify installations
for cmd in kind kubectl cilium hubble jq; do
    if command -v $cmd &> /dev/null; then
        VERSION=$($cmd version 2>&1 | head -n 1 || echo "installed")
        echo "✓ $cmd: $VERSION"
    else
        echo "✗ $cmd: NOT FOUND"
    fi
done

echo ""
echo "Next step:"
echo "  ./setup/02-create-cluster.sh"
