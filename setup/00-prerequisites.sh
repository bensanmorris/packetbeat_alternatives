#!/bin/bash
set -e

echo "=== Cilium/Packetbeat POC - Prerequisites Setup ==="
echo "This script configures RHEL9 for running Kind with Podman"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

echo "Step 1: Checking RHEL9 version..."
if ! grep -q "release 9" /etc/redhat-release; then
    echo "WARNING: This script is designed for RHEL9"
    echo "Current version: $(cat /etc/redhat-release)"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Step 2: Installing Podman (if not already installed)..."
dnf install -y podman podman-plugins

echo "Step 3: Checking cgroup version..."
# Use grep method which works across different Podman versions
if podman info 2>/dev/null | grep -q "cgroupVersion: v2"; then
    CGROUP_VERSION="v2"
elif podman info 2>/dev/null | grep -q "cgroup version: 2"; then
    CGROUP_VERSION="v2"
else
    CGROUP_VERSION="v1"
fi
echo "Current cgroup version: $CGROUP_VERSION"

if [ "$CGROUP_VERSION" != "v2" ]; then
    echo "Step 4: Enabling cgroup v2..."
    grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1"
    REBOOT_NEEDED=1
else
    echo "Step 4: cgroup v2 already enabled ✓"
    REBOOT_NEEDED=0
fi

echo "Step 5: Configuring systemd delegation..."
mkdir -p /etc/systemd/system/user@.service.d
cat > /etc/systemd/system/user@.service.d/delegate.conf <<EOF
[Service]
Delegate=yes
EOF

echo "Step 6: Loading iptables kernel modules..."
cat > /etc/modules-load.d/iptables.conf <<EOF
ip6_tables
ip6table_nat
ip_tables
iptable_nat
EOF

systemctl restart systemd-modules-load.service

echo "Step 7: Verifying iptables modules..."
if lsmod | grep -qE 'ip_tables|ip6_tables'; then
    echo "iptables modules loaded ✓"
else
    echo "WARNING: iptables modules may not be loaded correctly"
fi

echo "Step 8: Reloading systemd..."
systemctl daemon-reload

echo ""
echo "=== Prerequisites Setup Complete ==="
echo ""

if [ "$REBOOT_NEEDED" -eq 1 ]; then
    echo "⚠️  REBOOT REQUIRED ⚠️"
    echo ""
    echo "cgroup v2 has been enabled but requires a reboot."
    echo ""
    echo "After reboot, continue with:"
    echo "  cd cilium-packetbeat-poc"
    echo "  ./setup/01-install-tools.sh"
    echo ""
    read -p "Reboot now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    fi
else
    echo "✓ No reboot required"
    echo ""
    echo "Next step:"
    echo "  ./setup/01-install-tools.sh"
fi
