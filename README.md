# Cilium vs Packetbeat POC - RHEL9 + Podman

## TL;DR - Key Findings

**Surprising Result:** In flow-mode, Packetbeat is actually **30% smaller** than Hubble, not larger! The original 230:1 ratio was based on Packetbeat's transaction mode (capturing full HTTP payloads).

**The Real Difference:** It's not about storage—it's about **context vs granularity**:
- **Hubble:** Kubernetes-native (pod names, namespaces, policy verdicts) - Perfect for cloud-native troubleshooting
- **Packetbeat:** Network-native (per-flow byte/packet counters, duration) - Perfect for deep network analysis

**Byte Counter Reality:**
- **Cilium provides:** Cluster-wide aggregated byte metrics (`drop_bytes_total`, `forward_bytes_total`) - useful for overall traffic patterns
- **Cilium does NOT provide:** Per-endpoint or per-flow byte counters - cannot tell you "how many bytes pod X sent to pod Y"
- **Official source:** [Cilium Metrics Documentation - Drops/Forwards (L3/L4)](https://docs.cilium.io/en/stable/observability/metrics/#drops-forwards-l3-l4)
- **Packetbeat provides:** Per-flow byte/packet counters in every flow record - complete granularity

**Recommended Approach:** Run Hubble always-on for Kubernetes context + deploy Packetbeat on-demand (24-48 hours) when you need per-flow byte granularity.

📊 **[Read the full analysis report](data-sample/README.md)** - Complete comparison of 5,000 events from both tools, including storage efficiency, data richness comparison, coverage analysis, and recommended deployment strategy.

---

This repo contains everything needed to run a side-by-side comparison of Cilium/Hubble and Packetbeat on RHEL9 using Podman.

![Cilium capture screenshot](screenshot.png)

## Contents

```
cilium-packetbeat-poc/
├── README.md                    # This file
├── TEST-RESULTS-SUMMARY.md      # Latest test results and findings
├── diagnose-cilium.sh           # Troubleshoot Cilium installation issues
├── create-sample-data.sh        # Create sample data for Git upload
├── prepare-upload.sh            # Prepare test data for repository upload
├── analyze-collected-data.sh    # Analyze collected test data
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
│   ├── deploy-error-scenarios.sh    # Deploy all error test scenarios
│   ├── enable-l7-visibility.sh      # Enable L7 HTTP visibility for Cilium
│   ├── verify-l7-visibility.sh      # Verify L7 is working
│   ├── cilium-l7-policy.yaml        # Cilium L7 HTTP inspection policy
│   ├── cleanup-demo.sh              # Clean up demo namespace
│   ├── analyze-error-scenarios.sh   # Analyze error scenario results
│   ├── error-generator.yaml         # Continuous error generation
│   ├── backend-error-service.yaml   # Backend that returns specific status codes
│   ├── network-policy-tests.yaml    # Network policies for testing
│   ├── policy-violator.yaml         # Attempts policy violations
│   ├── ERROR-SCENARIOS-README.md    # Detailed error testing guide
│   ├── generate-traffic.sh          # Generate test traffic (original)
│   └── test-scenarios.sh            # Run specific test scenarios
├── collection/
│   ├── collect-hubble-data.sh   # Collect Hubble flows and metrics
│   ├── collect-packetbeat-data.sh # Collect Packetbeat captures
│   ├── extract-cilium-byte-metrics.py # Extract byte/packet counters from Prometheus
│   └── export-all.sh            # Export all data
├── analysis/
│   ├── generate-report.sh       # Generate comparison report
│   ├── compare-data.sh          # Compare data volume and coverage
│   ├── analyze-protocols.sh     # Protocol coverage analysis
│   └── resource-usage.sh        # Resource consumption comparison
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

# Wait for Cilium to be fully ready (can take 10-15 minutes on first run)
# Timeline:
#   0-2 min:  Pods scheduled, pulling images (500MB+)
#   2-5 min:  Init containers running
#   5-10 min: Main containers starting, Cilium agent initializing
#   10-15 min: All components ready, nodes become Ready
cilium status --wait

# If cilium status shows errors about "cilium.sock: connect: no such file or directory":
# This is NORMAL during startup - the agent process is still initializing
# Wait 3-5 more minutes and check again:
sleep 180
cilium status

# Troubleshooting: If pods stay in error state after 15 minutes, run diagnostics
# ./diagnose-cilium.sh

# Once Cilium shows all "OK", deploy Packetbeat
kubectl apply -f deploy/packetbeat-config.yaml
kubectl apply -f deploy/packetbeat-daemonset.yaml

# Enable Hubble port-forwarding (required for CLI access)
cilium hubble port-forward &
```

**Expected output from `cilium status --wait`:**
```
Cilium:             OK
Operator:           OK
Envoy DaemonSet:    OK
Hubble Relay:       OK
```

**Common during startup (NOT errors - just wait):**
```
Error: dial unix /var/run/cilium/cilium.sock: no such file or directory
→ Agent still initializing, wait 3-5 more minutes

Pods: Pending (image pull)
→ Normal, images are 500MB+, takes 2-5 minutes

Pods: Running but "not ready"
→ Normal, agent socket initializing, takes 5-10 minutes

Nodes: NotReady
→ Normal until Cilium CNI is running, then nodes become Ready
```

**Note:** The `hubble-metrics` service is created for compatibility, though byte/packet counters are extracted from eBPF maps rather than Prometheus metrics.

### 3. Deploy Error Scenarios (Recommended Test)
```bash
chmod +x testing/*.sh

# Create demo namespace
kubectl create namespace demo

# Deploy error generators and test applications
./testing/deploy-error-scenarios.sh

# Note: L7 HTTP visibility is optional and can cause connectivity issues
# The test works perfectly fine with L3/L4 flow data (IPs, ports, protocols)
# which is sufficient for the byte counter comparison

# Verify traffic is flowing
kubectl logs -n demo deployment/error-generator --tail=30
```

**Expected from error generator:**
```
✓ GET /status/400: 400
✓ GET /status/401: 401
✓ GET /status/404: 404
✓ GET /status/500: 500
```

**What you'll capture (L3/L4 mode):**
- Source/destination IPs and ports
- Protocol information (TCP/UDP)
- Network policy verdicts (FORWARDED/DROPPED)
- Pod identity and labels
- **Byte/packet counters** (from Cilium eBPF maps)

### 4. Generate Traffic (Let Run 30-60 Minutes)
```bash
# Error scenarios generate traffic automatically every 30 seconds
# Monitor in real-time (optional):
kubectl logs -f -n demo deployment/error-generator
```

### 5. Collect Data with Byte Metrics (after 30-60 minutes)

**Byte metrics are extracted directly from Cilium's eBPF maps** (Cilium 1.16+ removed per-endpoint byte counters from Prometheus metrics)

```bash
chmod +x collection/*.sh

# Collects:
# - Hubble flows (L3/L4 with pod context)
# - Cilium byte/packet metrics from eBPF maps
# - Packetbeat flows (with embedded byte counters)
./collection/export-all.sh
```

**Verify byte metrics were collected:**

```bash
# Check files were created
ls -lh data/hubble/cilium-byte-metrics.json
ls -lh data/hubble/byte-metrics-summary.txt

# View summary
cat data/hubble/byte-metrics-summary.txt
```

**Expected output:**
```
Cilium Byte/Packet Counter Summary
==================================================

Total endpoints:     6
Total ingress bytes: 1,234,567
Total egress bytes:  2,345,678
Total bytes:         3,580,245

Total ingress pkts:  12,345
Total egress pkts:   23,456
Total packets:       35,801

Top 10 endpoints by total bytes:
--------------------------------------------------
endpoint_1377            1,234,567 bytes
endpoint_2435              567,890 bytes
...
```

**How it works:**

The `extract-cilium-bpf-metrics.sh` script:
1. Connects to each Cilium pod
2. Runs `cilium bpf endpoint list` to get eBPF map data
3. Parses byte/packet counters for each endpoint
4. Aggregates into JSON format
5. Generates human-readable summary

**What gets collected:**
- Hubble flows (no byte counters in flow records)
- **Cilium byte/packet metrics** (extracted via `collection/extract-cilium-byte-metrics.py`)
- Packetbeat flows (with per-flow byte counters)

**New data files created:**
- `data/hubble/cilium-byte-metrics.json` - Byte/packet totals per pod (~12 KB)
- `data/hubble/byte-metrics-summary.txt` - Human-readable summary

### 6. Analyze Results
```bash
chmod +x testing/*.sh
# Generates comprehensive comparison report
./testing/analyze-error-scenarios.sh

# View the report
cat reports/error-scenarios-*.txt | less
```

### 7. Share Your Results (Optional)

```bash
# First, analyze what data you collected
./analyze-collected-data.sh

# Create a Git-friendly sample dataset (first 1000 events from each file)
# Typical size: ~10-20 MB (safe for Git)
./create-sample-data.sh 1000

# OR: Create summary package with reports and stats only (no raw data)
# Typical size: < 10 MB (includes reports, statistics, sample data)
./prepare-upload.sh

# Then commit to Git
git add data-sample/  # if using create-sample-data.sh
# OR
git add upload-package-*/  # if using prepare-upload.sh

git commit -m "Add test results: 230x storage difference (Hubble 17MB vs Packetbeat 3.9GB)"
git push
```

See [Sharing and Uploading Test Data](#sharing-and-uploading-test-data) section below for details.

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

## Testing network and protocol error scenarios

[An additional set of test scripts and config are provided here](/testing/ERROR-SCENARIOS-README.md) for testing specific error scenarios (useful for understanding the level of granularity captured by Cilium).

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

## Sharing and Uploading Test Data

### Latest Test Results

**February 5, 2026 Test Run:**
- **Hubble:** 12,232 flows, 17 MB total
- **Packetbeat:** 970,539 events, 3.9 GB total
- **Storage Ratio:** 230:1 (Packetbeat captures 230x more data)
- **Full Results:** See [TEST-RESULTS-SUMMARY.md](TEST-RESULTS-SUMMARY.md)

### Step 1: Analyze Your Collected Data

After running `./collection/export-all.sh`, analyze what you collected:

```bash
# Quick analysis of your data
./analyze-collected-data.sh
```

This shows:
- Total data size
- Number of Hubble flows captured
- Number of Packetbeat events captured
- Recommended upload strategy based on size

### Step 2: Create Sample Data for Git

Full test data (typically 100 MB - 4 GB) is too large for Git. Create a sample dataset:

```bash
# Create sample with first 1000 events per file (default)
# This creates ~10-20 MB of data - perfect for Git
./create-sample-data.sh 1000

# For smaller repos, use fewer events
# Creates ~5-10 MB - good for quick demos
./create-sample-data.sh 500

# For more comprehensive samples, use more events
# Creates ~50-100 MB - still Git-friendly but shows more patterns
./create-sample-data.sh 5000
```

This creates `data-sample/` directory with:
- First N events from each data file (Hubble flows and Packetbeat events)
- All statistics and metadata (already small files)
- Auto-generated README with usage examples and analysis commands

**Example: With 1000 events from your 4 GB dataset:**
- Hubble sample: ~1.4 MB (1000 flows from 12,232 total)
- Packetbeat sample: ~4 MB (1000 events from 970,539 total)
- Total sample size: ~10-15 MB

**Upload sample to Git:**
```bash
git add data-sample/
git commit -m "Add sample test data (1000 events per file)"
git push origin your-branch
```

### Step 3: Prepare Summary Package (Optional)

For a complete summary package with reports and statistics but WITHOUT raw event data:

```bash
# Create comprehensive summary package for Git upload
# This includes: reports, statistics, sample data, metadata
# Does NOT include: full 4 GB raw data files
# Typical size: < 10 MB (much smaller than create-sample-data.sh)
./prepare-upload.sh
```

**What this creates:**
1. `upload-package-YYYYMMDD-HHMMSS/` - Git-ready summary package containing:
   - All analysis reports from `reports/`
   - Statistics files (hubble-stats.txt, packetbeat-stats.txt)
   - Sample data (first 1000 events)
   - Metrics and cluster info
   - Auto-generated README

2. `test-results-YYYYMMDD-HHMMSS.tar.gz` - Compressed summary (~5-10 MB)
   - For easy sharing via email or Slack

3. `full-test-data-YYYYMMDD-HHMMSS.tar.gz` - Complete raw data (~1-2 GB compressed)
   - For GitHub Release or external storage
   - Contains all 12,232 Hubble flows and 970,539 Packetbeat events

**Upload summary package to Git:**
```bash
# Upload only the summary (< 10 MB)
git add upload-package-*/
git commit -m "Add test results summary: Hubble 17MB vs Packetbeat 3.9GB"
git push origin your-branch
```

**For full data, use GitHub Release or external storage (not Git):**
- The full-test-data archive is too large for Git
- See Step 4 below for sharing options

### Step 4: Share Full Data (If Needed)

For complete datasets (100 MB - 4 GB):

**Option A: GitHub Release**
1. Go to: https://github.com/your-username/your-repo/releases
2. Create new release
3. Upload `full-test-data-*.tar.gz` (supports up to 2 GB)

**Option B: External Storage**
- Google Drive, Dropbox, or AWS S3
- Upload `full-test-data-*.tar.gz`
- Add link to repository

See [UPLOAD-DATA-GUIDE.md](UPLOAD-DATA-GUIDE.md) for detailed upload strategies.

## Expected Outputs

After running `./collection/export-all.sh`:

**Hubble Data:**
- `data/hubble/hubble-flows-all.json` - Network flow data
- `data/hubble/cilium-byte-metrics.json` - **Byte/packet counters per pod** (NEW!)
- `data/hubble/byte-metrics-summary.txt` - Human-readable metrics summary
- `data/hubble/hubble-metrics-raw.txt` - Raw Prometheus metrics

**Packetbeat Data:**
- `data/packetbeat/packetbeat-combined.json` - Flow data with byte counters
- `data/packetbeat/packetbeat-stats.txt` - Statistics

**Other:**
- `data/resource-usage.json` - CPU/Memory usage
- `data/cluster/` - Cluster state snapshots

**Note:** The updated `collect-hubble-data.sh` script now automatically extracts byte/packet counters from Cilium's Prometheus metrics, enabling fair comparison with Packetbeat's per-flow byte counters.

After running `./testing/analyze-error-scenarios.sh`:
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
