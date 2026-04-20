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
echo "Step 4: Extracting Cilium byte/packet counters from eBPF maps..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/extract-cilium-bpf-metrics.sh" ]; then
    echo "  Using eBPF map extraction (Cilium 1.16+ compatible)..."
    "$SCRIPT_DIR/extract-cilium-bpf-metrics.sh" \
        "$DATA_DIR/cilium-byte-metrics.json" \
        "$DATA_DIR/byte-metrics-summary.txt"
else
    echo "  ⚠️  extract-cilium-bpf-metrics.sh not found"
    echo "{}" > "$DATA_DIR/cilium-byte-metrics.json"
fi

echo ""
echo "Step 5: Generating flow statistics..."
if [ -f "$DATA_DIR/hubble-flows-all.json" ]; then
    cat > "$DATA_DIR/hubble-stats.txt" <<STATSEOF
Hubble Flow Statistics
======================

Total flows: $(wc -l < "$DATA_DIR/hubble-flows-all.json")
HTTP flows: $(wc -l < "$DATA_DIR/hubble-flows-http.json" 2>/dev/null || echo "0")
DNS flows: $(wc -l < "$DATA_DIR/hubble-flows-dns.json" 2>/dev/null || echo "0")
Dropped flows: $(wc -l < "$DATA_DIR/hubble-flows-dropped.json" 2>/dev/null || echo "0")
STATSEOF
    echo "  ✓ Statistics generated"
fi

echo ""
echo "=== Hubble Data Collection Complete ==="
echo ""
echo "Data saved to: $DATA_DIR/"
ls -lh "$DATA_DIR/" | grep -v "^total"

echo ""
echo "Summary:"
FLOW_COUNT=$(wc -l < "$DATA_DIR/hubble-flows-all.json" 2>/dev/null || echo "0")
FLOW_SIZE=$(du -h "$DATA_DIR/hubble-flows-all.json" 2>/dev/null | cut -f1 || echo "N/A")
METRICS_SIZE=$(du -h "$DATA_DIR/cilium-byte-metrics.json" 2>/dev/null | cut -f1 || echo "N/A")
echo "  Flows collected:  $FLOW_COUNT ($FLOW_SIZE)"
echo "  Byte metrics:     $METRICS_SIZE"
echo ""
echo "Next: Run ./collection/collect-packetbeat-data.sh"
