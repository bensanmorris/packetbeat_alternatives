# Packetbeat vs Cilium/Hubble - POC Comparison Analysis

**Test Duration:** 1 hour  
**Date:** April 17, 2026  
**Sample Size:** 5,000 events from each tool

---

## Executive Summary

**Surprising Result:** Packetbeat in flow-mode is actually **MORE storage efficient** than Hubble for the same time period, while providing per-flow byte/packet counters that Hubble requires a separate Prometheus query to obtain.

However, Hubble provides critical **Kubernetes-native context** (pod names, namespaces, network policy verdicts) that Packetbeat cannot match.

---

## Test Data Files

This directory contains sample data collected during the 1-hour test run. Below is a breakdown of all files:

### Hubble Data Files

| File | Size | Records | Description |
|------|------|---------|-------------|
| [hubble-flows-all.json](hubble/hubble-flows-all.json) | 6.4 MB | 5,000 | All Hubble flows (all namespaces) |
| [hubble-flows-demo.json](hubble/hubble-flows-demo.json) | 3.6 MB | 2,386 | Flows from demo namespace only |
| [hubble-flows-dropped.json](hubble/hubble-flows-dropped.json) | 23 KB | 16 | Dropped flows (policy violations) |
| [hubble-flows-http.json](hubble/hubble-flows-http.json) | 482 B | 3 | HTTP L7 flows (if L7 enabled) |
| [hubble-flows-dns.json](hubble/hubble-flows-dns.json) | 482 B | 3 | DNS flows |
| [hubble-stats.txt](hubble/hubble-stats.txt) | 111 B | - | Flow statistics summary |
| [cilium-status.txt](hubble/cilium-status.txt) | 2.3 KB | - | Cilium status at collection time |

**Note:** Hubble flows do NOT contain per-flow byte/packet counters. Cilium provides cluster-wide aggregated byte metrics (`drop_bytes_total`, `forward_bytes_total`) but not per-endpoint or per-flow counters. See [Cilium Metrics Documentation](https://docs.cilium.io/en/stable/observability/metrics/#drops-forwards-l3-l4).

### Packetbeat Data Files

| File | Size | Records | Description |
|------|------|---------|-------------|
| [packetbeat-combined.json](packetbeat/packetbeat-combined.json) | 4.5 MB | 5,000 | All Packetbeat flow records (sample) |
| [packetbeat-stats.txt](packetbeat/packetbeat-stats.txt) | 3.3 KB | - | Event statistics summary |

**Note:** Every Packetbeat flow record includes per-flow byte/packet counters (100% coverage).

### Cluster Metadata Files

| File | Size | Description |
|------|------|-------------|
| [cluster/nodes.txt](cluster/nodes.txt) | 719 B | Kubernetes nodes information |
| [cluster/all-pods.txt](cluster/all-pods.txt) | 6.0 KB | All pods running during test |
| [cluster/all-services.txt](cluster/all-services.txt) | 1.3 KB | All services configured |
| [cluster/cilium-status.txt](cluster/cilium-status.txt) | 2.3 KB | Cilium status snapshot |

### Resource Metrics Files

| File | Size | Description |
|------|------|-------------|
| [metrics/cilium-resources.json](metrics/cilium-resources.json) | 186 B | Cilium pod resource usage |
| [metrics/packetbeat-resources.json](metrics/packetbeat-resources.json) | 142 B | Packetbeat pod resource usage |
| [metrics/pod-resources.txt](metrics/pod-resources.txt) | 33 B | Summary of resource consumption |

---

## Storage Comparison

| Metric | Hubble (All Flows) | Hubble (Demo Only) | Packetbeat (Flow Mode) |
|--------|-------------------|-------------------|----------------------|
| **Event Count** | 5,000 flows | 2,386 flows | 5,000 events |
| **Storage Size** | 6.37 MB | 3.58 MB | 4.42 MB |
| **Bytes/Event** | 1,274 bytes | 1,500 bytes | 884 bytes |
| **Monthly Projection** | ~4.5 GB/month | ~2.5 GB/month | ~3.1 GB/month |

**Key Finding:** Packetbeat is actually **30% smaller** than Hubble (all flows) and only **23% larger** than Hubble (demo-filtered).

---

## Data Richness Comparison

### Hubble Provides ✅

- **Pod/Namespace Context:** Full Kubernetes awareness
  - Pod names, namespaces, labels
  - Service context
  - Identity tracking
  
- **Network Policy Verdicts:**
  - FORWARDED (41.0%)
  - TRACED (34.4%)
  - TRANSLATED (24.0%)
  - DROPPED (0.5%)
  
- **Security Context:**
  - Which policies allowed/denied traffic
  - Identity-based tracking
  - Cilium-specific metadata

### Hubble Missing ❌

- **Per-Flow Byte Counters:** Not in flow records
  - Available via separate Prometheus metrics query
  - Requires additional scraping
  - Pod-level aggregation only (not per-flow)
  
- **Per-Flow Packet Counters:** Not in flow records
  - Same limitations as byte counters

### Packetbeat Provides ✅

- **Per-Flow Byte Counters:** Embedded in every event
  - Total bytes: 854
  - Source bytes: 418
  - Destination bytes: 436
  - 100% coverage
  
- **Per-Flow Packet Counters:** Complete breakdown
  - Total packets: 9
  - Source packets
  - Destination packets
  
- **Flow Duration:** Precise timing
  - Start/end timestamps
  - Duration in nanoseconds
  - Average flow duration available

### Packetbeat Missing ❌

- **Pod Context:** Only IP addresses
  - No pod names
  - No namespace information
  - No Kubernetes labels
  
- **Policy Verdicts:** No policy awareness
  - Cannot show which policy allowed/denied
  - No security context

---

## Coverage Analysis

### Hubble (Demo Namespace - 2,386 flows)

**Verdicts:**
- FORWARDED: 978 flows (41.0%) - Allowed by policy
- TRACED: 820 flows (34.4%) - Pre-translation tracking
- TRANSLATED: 573 flows (24.0%) - Service translation
- DROPPED: 12 flows (0.5%) - Policy violations
- UNKNOWN: 3 flows (0.1%)

**Protocols:**
- UDP: 1,767 flows (74.1%) - Mostly DNS
- TCP: 616 flows (25.8%) - HTTP traffic
- OTHER: 3 flows (0.1%)

### Packetbeat (5,000 events across all namespaces)

**Protocols:**
- TCP: 2,646 events (52.9%)
- UDP: 2,240 events (44.8%)
- ICMP: 59 events (1.2%)
- IPv6-ICMP: 40 events (0.8%)
- Unknown: 15 events (0.3%)

**Byte Counters:**
- 100% coverage (5,000/5,000 events)
- Average: 3,271 bytes per flow
- Total sampled: 327,104 bytes in 100 flows

---

## Real-World Implications

### Scenario 1: Always-On Observability

**Winner: Cilium/Hubble**

- **Storage:** ~4.5 GB/month (very manageable)
- **Context:** Full Kubernetes awareness essential for troubleshooting
- **Security:** Policy verdicts show which traffic is allowed/denied
- **Cost:** Minimal storage, native to cluster

**Byte Counters Solution:**
- Query Cilium Prometheus metrics separately
- Pod-level aggregation (not per-flow)
- Additional ~12 KB per snapshot

### Scenario 2: Detailed Investigation (24-48 hours)

**Winner: Packetbeat**

- **Storage:** ~0.2 GB per 48-hour investigation
- **Granularity:** Per-flow byte/packet counters
- **Duration:** Flow timing for performance analysis
- **Use Case:** Deep-dive network troubleshooting

**Context Gap:**
- Correlate IPs to pods manually
- No policy verdict information
- Limited to IP-level analysis

---

## Recommended Strategy

### Primary: Cilium/Hubble (Always-On)

**Enable permanently for:**
- Pod-aware network observability
- Network policy debugging
- Security incident response
- Kubernetes-native troubleshooting

**Storage:** ~54 GB/year

**Byte Counter Strategy:**
- Use Cilium Prometheus metrics for pod-level byte/packet totals
- Scrape `hubble-metrics:9965/metrics` every 15-60 seconds
- Store pod-aggregated counters (not per-flow)
- Sufficient for capacity planning and trend analysis

### Secondary: Packetbeat (On-Demand)

**Deploy for 24-48 hours when:**
- Investigating specific performance issues
- Need per-flow byte/packet granularity
- Analyzing flow duration patterns
- Troubleshooting non-Kubernetes traffic

**Storage:** ~0.2 GB per investigation

**When NOT needed:**
- Standard troubleshooting (use Hubble)
- Policy debugging (use Hubble)
- Pod-to-pod issues (use Hubble)

---

## Verdict Count Analysis

The Hubble verdict distribution is particularly valuable:

- **FORWARDED (41%):** Traffic explicitly allowed by network policy
- **TRACED (34%):** Initial packet tracking before translation
- **TRANSLATED (24%):** Service ClusterIP → Pod IP translation
- **DROPPED (0.5%):** Policy violations - critical for security!

**These verdicts are unique to Cilium/Hubble and cannot be obtained from Packetbeat.**

---

## Key Insights

### 1. Storage is NOT the differentiator

Both tools have negligible storage requirements. The decision should be based on **data richness**, not storage efficiency.

### 2. Hubble's Kubernetes context is invaluable

Troubleshooting "why is pod X unable to reach pod Y?" is trivial with Hubble, nearly impossible with Packetbeat.

### 3. Byte counters have different use cases

- **Hubble (via Prometheus):** Pod-level aggregation for capacity planning
- **Packetbeat:** Per-flow granularity for performance analysis

### 4. Packetbeat is surprisingly efficient in flow-mode

The old comparison showing 230:1 ratio was based on **transaction mode** (capturing full HTTP request/response). In flow mode, Packetbeat is only 1.2x larger than Hubble.

### 5. On-demand Packetbeat is the sweet spot

Run Packetbeat for 24-48 hours when you need detailed byte-level analysis. Don't run it always-on when Hubble provides better context for 99% of use cases.

---

## Sample Data Structures

### Hubble Flow (Kubernetes-Native)

```json
{
  "flow": {
    "verdict": "FORWARDED",
    "source": {
      "namespace": "demo",
      "pod_name": "error-generator-79846b7484-8dw9z",
      "labels": ["k8s:app=error-generator"]
    },
    "destination": {
      "namespace": "demo",
      "pod_name": "backend-error-capable-5f89455bc8-c4mtc"
    },
    "l4": {
      "TCP": {
        "destination_port": 80
      }
    }
  }
}
```

**Strengths:** Immediate pod/namespace context, policy verdict  
**Weakness:** No byte counters in flow record

### Packetbeat Flow (Network-Centric)

```json
{
  "source": {
    "ip": "10.244.1.154",
    "port": 50600,
    "bytes": 524,
    "packets": 6
  },
  "destination": {
    "ip": "10.244.2.27",
    "port": 80,
    "bytes": 417,
    "packets": 4
  },
  "network": {
    "bytes": 941,
    "packets": 10,
    "transport": "tcp"
  },
  "event": {
    "duration": 13608177103
  }
}
```

**Strengths:** Complete byte/packet breakdown, flow duration  
**Weakness:** No pod context, just IPs

---

## Conclusion

**The original hypothesis was partially wrong:**

We expected Packetbeat to be massively larger due to the 230:1 ratio seen in transaction mode. In reality, **Packetbeat in flow-mode is actually 30% smaller than Hubble** for the same time period.

**The real difference is not storage, but context:**

- **Hubble:** Kubernetes-native, policy-aware, perfect for cloud-native troubleshooting
- **Packetbeat:** Network-centric, byte-accurate, perfect for deep protocol analysis

**The recommended approach:**

1. **Run Hubble always-on** for Kubernetes-native observability
2. **Get byte counters from Cilium Prometheus metrics** (pod-level aggregation)
3. **Deploy Packetbeat on-demand** when you need per-flow byte granularity

**Value:** Best of both worlds - Kubernetes context 24/7 + detailed network analysis when needed

---

## Next Steps

1. **Enable Hubble permanently** in production clusters
2. **Configure Prometheus scraping** of Cilium metrics for byte counters
3. **Create runbooks** for deploying Packetbeat during investigations
4. **Document** when to use each tool
5. **Train teams** on interpreting Hubble verdicts and policy context

---

**Test conducted by:** Ben Morris  
**Infrastructure:** Kind cluster, Cilium 1.18.5, Packetbeat 8.11.0  
**Sample period:** 1 hour of continuous traffic generation  
**Sample size:** 5,000 events from each tool (extracted from full dataset)
