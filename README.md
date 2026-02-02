# Cilium vs Packetbeat POC - RHEL9 + Podman

This package contains everything needed to run a side-by-side comparison of Cilium/Hubble and Packetbeat on RHEL9 using Podman.

## Contents

```
cilium-packetbeat-poc/
├── README.md                    # This file
├── setup/
│   ├── 00-prerequisites.sh      # System prerequisites setup
│   ├── 01-install-tools.sh      # Install Kind, kubectl, Cilium CLI, Hubble CLI
│   ├── 02-create-cluster-rootful.sh # Create Kind cluster with Podman
│   └── 03-verify-setup.sh       # Verify installation
├── deploy/
│   ├── kind-config.yaml         # Kind cluster configuration
│   ├── cilium-install.sh        # Install Cilium + Hubble
│   ├── packetbeat-config.yaml   # Packetbeat ConfigMap
│   ├── packetbeat-daemonset.yaml # Packetbeat deployment
│   └── test-app.yaml            # Demo microservices application
├── testing/
│   ├── generate-traffic.sh      # Generate test traffic
│   ├── test-scenarios.sh        # Run specific test scenarios
│   └── workloads/
│       ├── http-workload.yaml   # HTTP traffic generator
│       ├── dns-workload.yaml    # DNS query generator
│       └── failed-workload.yaml # Failed connection generator
├── collection/
│   ├── collect-hubble-data.sh   # Collect Hubble flows and metrics
│   ├── collect-packetbeat-data.sh # Collect Packetbeat captures
│   └── export-all.sh            # Export all data
├── analysis/
│   ├── compare-data.sh          # Compare data volume and coverage
│   ├── analyze-protocols.sh     # Protocol coverage analysis
│   ├── resource-usage.sh        # Resource consumption comparison
│   └── generate-report.sh       # Generate comparison report
└── cleanup/
    ├── cleanup-all.sh           # Remove everything
    └── cleanup-data-only.sh     # Keep cluster, remove data
```

## Quick Start

### 1. Prerequisites Setup (one-time)
```bash
cd cilium-packetbeat-poc
chmod +x setup/*.sh
sudo ./setup/00-prerequisites.sh
# System will reboot after this step
```

After reboot:
```bash
cd cilium-packetbeat-poc
./setup/01-install-tools.sh
./setup/02-create-cluster-rootful.sh
./setup/03-verify-setup.sh
```

### 2. Deploy Monitoring Stack
```bash
chmod +x deploy/*.sh
./deploy/cilium-install.sh
kubectl apply -f deploy/packetbeat-config.yaml
kubectl apply -f deploy/packetbeat-daemonset.yaml
kubectl apply -f deploy/test-app.yaml
```

### 3. Generate Traffic
```bash
chmod +x testing/*.sh
./testing/generate-traffic.sh
```

### 4. Collect Data (after 1-24 hours)
```bash
chmod +x collection/*.sh
./collection/export-all.sh
```

### 5. Analyze Results
```bash
chmod +x analysis/*.sh
./analysis/generate-report.sh
```

## Manual Steps

### Access Hubble UI
```bash
cilium hubble ui
# Opens browser at http://localhost:12000
```

### View Live Hubble Flows
```bash
hubble observe --namespace demo
```

### View Packetbeat Logs
```bash
kubectl logs -n monitoring -l app=packetbeat -f
```

## Troubleshooting

### If Kind fails to start
Check cgroup version:
```bash
podman info | grep -i cgroup
```
Should show `cgroupVersion: v2`

### If Hubble doesn't start
```bash
cilium status
cilium hubble enable --ui
```

### If Packetbeat pods are stuck
```bash
kubectl describe pod -n monitoring -l app=packetbeat
```

## Data Collection Timeline

- **15 minutes**: Initial validation data
- **1 hour**: Short-term comparison
- **24 hours**: Full production-like comparison (recommended)

## Expected Outputs

After running `./collection/export-all.sh`:
- `data/hubble-flows.json` - Hubble flow data
- `data/hubble-metrics.txt` - Prometheus metrics
- `data/packetbeat-data/` - Packetbeat capture files
- `data/resource-usage.json` - CPU/Memory usage

After running `./analysis/generate-report.sh`:
- `reports/comparison-report.txt` - Summary report
- `reports/protocol-coverage.txt` - Protocol analysis
- `reports/resource-usage.txt` - Resource comparison

## Cleanup

Keep cluster, remove data:
```bash
./cleanup/cleanup-data-only.sh
```

Remove everything:
```bash
./cleanup/cleanup-all.sh
```

## Support

For issues specific to:
- **Kind + Podman**: https://kind.sigs.k8s.io/docs/user/rootless/
- **Cilium**: https://docs.cilium.io/
- **Packetbeat**: https://www.elastic.co/guide/en/beats/packetbeat/

## Notes

- This POC runs entirely on your laptop using Podman
- No cloud resources or external dependencies required
- All data stays local
- Safe to run on development machines
