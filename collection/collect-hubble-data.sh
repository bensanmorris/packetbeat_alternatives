#!/bin/bash
set -e

echo "=== Collecting Hubble Data ==="
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
echo "Step 2: Collecting Hubble metrics..."
# Port-forward Hubble metrics in background
kubectl port-forward -n kube-system svc/hubble-metrics 9965:9965 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

if curl -s http://localhost:9965/metrics > "$DATA_DIR/hubble-metrics.txt"; then
    echo "  ✓ Metrics collected"
else
    echo "  ⚠️  Could not collect metrics"
fi

# Kill port-forward
kill $PF_PID 2>/dev/null || true

echo ""
echo "Step 3: Collecting Cilium status..."
cilium status > "$DATA_DIR/cilium-status.txt" 2>&1 || true

echo ""
echo "Step 4: Generating flow statistics..."
if [ -f "$DATA_DIR/hubble-flows-all.json" ]; then
    cat > "$DATA_DIR/hubble-stats.txt" <<EOF
Hubble Flow Statistics
======================

Total flows: $(cat "$DATA_DIR/hubble-flows-all.json" | wc -l)
HTTP flows: $(cat "$DATA_DIR/hubble-flows-http.json" 2>/dev/null | wc -l || echo "0")
DNS flows: $(cat "$DATA_DIR/hubble-flows-dns.json" 2>/dev/null | wc -l || echo "0")
Dropped flows: $(cat "$DATA_DIR/hubble-flows-dropped.json" 2>/dev/null | wc -l || echo "0")

Verdicts:
$(cat "$DATA_DIR/hubble-flows-all.json" | jq -r '.verdict // "UNKNOWN"' 2>/dev/null | sort | uniq -c | sort -rn)

Top source IPs:
$(cat "$DATA_DIR/hubble-flows-all.json" | jq -r '.source.identity.labels[] // empty' 2>/dev/null | sort | uniq -c | sort -rn | head -10)

Top destination IPs:
$(cat "$DATA_DIR/hubble-flows-all.json" | jq -r '.destination.identity.labels[] // empty' 2>/dev/null | sort | uniq -c | sort -rn | head -10)
EOF
    echo "  ✓ Statistics generated"
fi

echo ""
echo "=== Hubble Data Collection Complete ==="
echo ""
echo "Data saved to: $DATA_DIR/"
ls -lh "$DATA_DIR/"
