# Cilium vs Packetbeat POC - RHEL9 + Podman

Packetbeat being designed around Elastic ingest is quite verbose (approx 2-5k of metadata per event) vs Cilium's 200-500 bytes. This repo contains everything needed to run a side-by-side comparison of Cilium/Hubble and Packetbeat on RHEL9 using Podman.

[Results on local RHEL9 demo machine](./reports/comparison-report-20260203-114043.txt)

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
```

### 2. Deploy Monitoring Stack
```bash
chmod +x deploy/*.sh
./deploy/cilium-install.sh
kubectl apply -f deploy/packetbeat-daemonset.yaml
kubectl apply -f deploy/packetbeat-config.yaml
kubectl apply -f deploy/test-app.yaml

# Enable Hubble port-forwarding (required for CLI access)
cilium hubble port-forward &
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
# First, ensure Hubble port-forwarding is active
cilium hubble port-forward &

# Then observe flows
hubble observe --namespace demo

# Filter by specific criteria
hubble observe --namespace demo --protocol http
hubble observe --namespace demo --verdict DROPPED
```

### View Packetbeat Logs
```bash
kubectl logs -n monitoring -l app=packetbeat -f
```

### Check Resource Usage
```bash
# View pod resource consumption
kubectl top pods --all-namespaces

# Check Cilium status
cilium status

# Check Packetbeat status
kubectl get pods -n monitoring
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

### If Hubble observe fails with "connection refused"
Start the port-forward:
```bash
cilium hubble port-forward &

# Or manually:
kubectl port-forward -n kube-system svc/hubble-relay 4245:4245 &
```

### If Packetbeat pods are stuck
```bash
kubectl describe pod -n monitoring -l app=packetbeat
```

### If cluster creation fails with delegation error
Try using rootful Podman (which you should already be doing):
```bash
./setup/02-create-cluster-rootful.sh
```

Or see `DELEGATION-TROUBLESHOOTING.md` for detailed solutions.

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

## What Gets Compared

The POC compares Cilium/Hubble vs Packetbeat on:

1. **Data Volume & Efficiency**
   - Storage requirements
   - JSON verbosity and redundancy
   - Compression ratios

2. **Protocol Coverage**
   - HTTP/HTTPS requests, methods, status codes
   - DNS queries and responses
   - TCP/UDP flows and connection states
   - TLS/SSL certificate information
   - Database protocols (MySQL, PostgreSQL, Redis)

3. **Network Visibility**
   - Connection tracking
   - Failed/dropped connections with reasons
   - Policy enforcement visibility
   - Service-to-service communication

4. **Kubernetes Context**
   - **Hubble**: Pod names, labels, namespace context
   - **Packetbeat**: IP addresses, ports, packet details

5. **Resource Overhead**
   - CPU and memory consumption
   - Network overhead from monitoring
   - Scalability implications

6. **Operational Considerations**
   - Query performance
   - Integration options (Elastic Stack vs Prometheus/Grafana)
   - Ease of troubleshooting

## Key Differences You'll Observe

| Aspect | Packetbeat | Cilium/Hubble |
|--------|------------|---------------|
| **Granularity** | Packet-level (very detailed) | Flow-level (aggregated) |
| **Context** | IP addresses, ports | Pod names, Kubernetes labels |
| **Data Volume** | High (verbose JSON) | Lower (efficient) |
| **Redundancy** | High (metadata repeated per event) | Low (normalized) |
| **Use Case** | Deep packet inspection, forensics | Kubernetes-native monitoring |
| **Overhead** | Higher CPU/memory | Lower CPU/memory |
| **Integration** | Elastic Stack | Prometheus, Grafana |

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
- Rootful Podman is used to avoid systemd delegation issues
- Traffic generators create realistic HTTP, DNS, and failed connection patterns
- Both monitoring tools capture the same traffic simultaneously for accurate comparison
