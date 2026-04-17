#!/bin/bash
set -e

echo "=== Collecting Hubble Data with Byte Metrics ==="
echo ""

# Create data directory
DATA_DIR="data/hubble"
mkdir -p "$DATA_DIR"

echo "Step 1: Collecting Hubble flows..."
echo "  Collecting last 10000 flows..."
hubble observe --last 10000 --output json > "$DATA_DIR/hubble-flows-all.json" 2>/dev/null || {
    echo "  ⚠️  Could not collect flows. Is Hubble running?"
    echo "  Try: cilium hubble enable --ui"
}

echo "  Collecting flows from demo namespace..."
hubble observe --namespace demo --last 5000 --output json > "$DATA_DIR/hubble-flows-demo.json" 2>/dev/null || true

echo "  Collecting HTTP flows..."
hubble observe --protocol http --last 5000 --output json > "$DATA_DIR/hubble-flows-http.json" 2>/dev/null || true

echo "  Collecting dropped flows..."
hubble observe --verdict DROPPED --last 5000 --output json > "$DATA_DIR/hubble-flows-dropped.json" 2>/dev/null || true

echo "  Collecting DNS flows..."
hubble observe --protocol dns --last 5000 --output json > "$DATA_DIR/hubble-flows-dns.json" 2>/dev/null || true

echo ""
echo "Step 2: Collecting Hubble Prometheus metrics..."
# Port-forward Hubble metrics in background
kubectl port-forward -n kube-system svc/hubble-metrics 9965:9965 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

if curl -s http://localhost:9965/metrics > "$DATA_DIR/hubble-metrics-raw.txt"; then
    echo "  ✓ Raw Prometheus metrics collected"
else
    echo "  ⚠️  Could not collect metrics"
fi

# Kill port-forward
kill $PF_PID 2>/dev/null || true

echo ""
echo "Step 3: Collecting Cilium status..."
cilium status > "$DATA_DIR/cilium-status.txt" 2>&1 || true

echo ""
echo "Step 4: Extracting Cilium byte/packet counters..."

if [ -f "$DATA_DIR/hubble-metrics-raw.txt" ]; then
    echo "  Parsing byte/packet metrics from Prometheus data..."
    
    # Extract and parse byte/packet counters into JSON
    python3 - <<'PYTHON_SCRIPT' > "$DATA_DIR/cilium-byte-metrics.json" 2>/dev/null || {
        echo "{}" > "$DATA_DIR/cilium-byte-metrics.json"
    }
import re
import json

metrics = {}

try:
    with open('data/hubble/hubble-metrics-raw.txt', 'r') as f:
        for line in f:
            # Skip comments and empty lines
            if line.startswith('#') or not line.strip():
                continue
            
            # Parse endpoint byte metrics
            # Format: cilium_endpoint_egress_bytes_total{endpoint_id="123",namespace="demo",pod="frontend-abc"} 12345
            
            # Egress bytes
            match = re.match(r'cilium_endpoint_egress_bytes_total\{[^}]*namespace="([^"]+)"[^}]*pod="([^"]+)"[^}]*\}\s+(\d+)', line)
            if match:
                namespace, pod, bytes_val = match.groups()
                key = f"{namespace}/{pod}"
                if key not in metrics:
                    metrics[key] = {}
                metrics[key]['egress_bytes'] = int(bytes_val)
            
            # Ingress bytes
            match = re.match(r'cilium_endpoint_ingress_bytes_total\{[^}]*namespace="([^"]+)"[^}]*pod="([^"]+)"[^}]*\}\s+(\d+)', line)
            if match:
                namespace, pod, bytes_val = match.groups()
                key = f"{namespace}/{pod}"
                if key not in metrics:
                    metrics[key] = {}
                metrics[key]['ingress_bytes'] = int(bytes_val)
            
            # Egress packets
            match = re.match(r'cilium_endpoint_egress_packets_total\{[^}]*namespace="([^"]+)"[^}]*pod="([^"]+)"[^}]*\}\s+(\d+)', line)
            if match:
                namespace, pod, packets_val = match.groups()
                key = f"{namespace}/{pod}"
                if key not in metrics:
                    metrics[key] = {}
                metrics[key]['egress_packets'] = int(packets_val)
            
            # Ingress packets
            match = re.match(r'cilium_endpoint_ingress_packets_total\{[^}]*namespace="([^"]+)"[^}]*pod="([^"]+)"[^}]*\}\s+(\d+)', line)
            if match:
                namespace, pod, packets_val = match.groups()
                key = f"{namespace}/{pod}"
                if key not in metrics:
                    metrics[key] = {}
                metrics[key]['ingress_packets'] = int(packets_val)
    
    # Calculate totals for each pod
    for key in metrics:
        metrics[key]['total_bytes'] = metrics[key].get('egress_bytes', 0) + metrics[key].get('ingress_bytes', 0)
        metrics[key]['total_packets'] = metrics[key].get('egress_packets', 0) + metrics[key].get('ingress_packets', 0)
    
    # Output JSON
    print(json.dumps(metrics, indent=2, sort_keys=True))
    
except Exception as e:
    # Fallback to empty JSON if parsing fails
    print("{}")
    import sys
    print(f"Warning: Failed to parse metrics: {e}", file=sys.stderr)
PYTHON_SCRIPT
    
    # Check if metrics were extracted
    if [ -s "$DATA_DIR/cilium-byte-metrics.json" ] && grep -q "egress_bytes" "$DATA_DIR/cilium-byte-metrics.json" 2>/dev/null; then
        POD_COUNT=$(grep -c '"egress_bytes"' "$DATA_DIR/cilium-byte-metrics.json" || echo "0")
        METRICS_SIZE=$(du -h "$DATA_DIR/cilium-byte-metrics.json" | cut -f1)
        echo "  ✓ Byte/packet metrics extracted: $POD_COUNT pods, $METRICS_SIZE"
    else
        echo "  ⚠️  No byte metrics found (no endpoints with traffic yet?)"
        echo "{}" > "$DATA_DIR/cilium-byte-metrics.json"
    fi
else
    echo "  ⚠️  Skipping byte metrics (Prometheus data not available)"
    echo "{}" > "$DATA_DIR/cilium-byte-metrics.json"
fi

echo ""
echo "Step 5: Generating statistics and summaries..."

# Generate flow statistics
if [ -f "$DATA_DIR/hubble-flows-all.json" ]; then
    cat > "$DATA_DIR/hubble-stats.txt" <<EOF
Hubble Flow Statistics
======================

Total flows: $(wc -l < "$DATA_DIR/hubble-flows-all.json")
HTTP flows: $(wc -l < "$DATA_DIR/hubble-flows-http.json" 2>/dev/null || echo "0")
DNS flows: $(wc -l < "$DATA_DIR/hubble-flows-dns.json" 2>/dev/null || echo "0")
Dropped flows: $(wc -l < "$DATA_DIR/hubble-flows-dropped.json" 2>/dev/null || echo "0")

Verdicts:
$(cat "$DATA_DIR/hubble-flows-all.json" | jq -r '.flow.verdict // "UNKNOWN"' 2>/dev/null | sort | uniq -c | sort -rn || echo "(jq not available)")

Top source labels:
$(cat "$DATA_DIR/hubble-flows-all.json" | jq -r '.flow.source.labels[]? // empty' 2>/dev/null | sort | uniq -c | sort -rn | head -5 || echo "(jq not available)")
EOF
    echo "  ✓ Flow statistics generated"
fi

# Generate byte metrics summary if python3/jq available
if [ -f "$DATA_DIR/cilium-byte-metrics.json" ] && command -v python3 &> /dev/null; then
    python3 - <<'PYTHON_SUMMARY' > "$DATA_DIR/byte-metrics-summary.txt" 2>/dev/null || echo "Byte metrics summary: see cilium-byte-metrics.json" > "$DATA_DIR/byte-metrics-summary.txt"
import json

with open('data/hubble/cilium-byte-metrics.json', 'r') as f:
    metrics = json.load(f)

demo_metrics = {k: v for k, v in metrics.items() if k.startswith('demo/')}

print("Cilium Byte/Packet Metrics Summary")
print("=" * 50)
print()

if demo_metrics:
    total_egress = sum(m.get('egress_bytes', 0) for m in demo_metrics.values())
    total_ingress = sum(m.get('ingress_bytes', 0) for m in demo_metrics.values())
    total_bytes = sum(m.get('total_bytes', 0) for m in demo_metrics.values())
    total_packets = sum(m.get('total_packets', 0) for m in demo_metrics.values())
    
    print(f"Demo namespace totals:")
    print(f"  Egress bytes:  {total_egress:,} ({total_egress / 1048576:.1f} MB)")
    print(f"  Ingress bytes: {total_ingress:,} ({total_ingress / 1048576:.1f} MB)")
    print(f"  Total bytes:   {total_bytes:,} ({total_bytes / 1048576:.1f} MB)")
    print(f"  Total packets: {total_packets:,}")
    print()
    print("Top 5 pods by total bytes:")
    
    sorted_pods = sorted(demo_metrics.items(), key=lambda x: x[1].get('total_bytes', 0), reverse=True)[:5]
    for pod, stats in sorted_pods:
        pod_name = pod.split('/')[-1]
        mb = stats.get('total_bytes', 0) / 1048576
        print(f"  {pod_name[:40]:40s} {mb:8.2f} MB")
else:
    print("No metrics found for demo namespace")
PYTHON_SUMMARY
    
    echo "  ✓ Byte metrics summary generated"
fi

echo ""
echo "=== Hubble Data Collection Complete ==="
echo ""
echo "Data saved to: $DATA_DIR/"
echo ""
ls -lh "$DATA_DIR/" | grep -v "^total" | awk '{printf "  %-40s %8s\n", $9, $5}'

echo ""
echo "Summary:"
FLOW_COUNT=$(wc -l < "$DATA_DIR/hubble-flows-all.json" 2>/dev/null || echo "0")
FLOW_SIZE=$(du -h "$DATA_DIR/hubble-flows-all.json" 2>/dev/null | cut -f1 || echo "N/A")
METRICS_SIZE=$(du -h "$DATA_DIR/cilium-byte-metrics.json" 2>/dev/null | cut -f1 || echo "N/A")
echo "  Flows collected:  $FLOW_COUNT ($FLOW_SIZE)"
echo "  Byte metrics:     $METRICS_SIZE"
echo ""
echo "Next: Run ./collection/collect-packetbeat-data.sh"
