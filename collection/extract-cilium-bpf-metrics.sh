#!/bin/bash
set -e

# Extract byte/packet counters from Cilium eBPF maps
# This is needed because Cilium 1.16+ removed per-endpoint byte counters from Prometheus metrics

OUTPUT_FILE="${1:-data/hubble/cilium-byte-metrics.json}"
SUMMARY_FILE="${2:-data/hubble/byte-metrics-summary.txt}"

echo "=== Extracting Cilium Byte/Packet Counters from eBPF Maps ==="
echo ""

# Create output directory
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Get list of Cilium pods
CILIUM_PODS=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[*].metadata.name}')

echo "Collecting endpoint statistics from Cilium pods..."
echo ""

# Create temporary file for raw data
TEMP_FILE=$(mktemp)

# Collect endpoint stats from all Cilium pods
for POD in $CILIUM_PODS; do
    echo "  Collecting from $POD..."
    kubectl exec -n kube-system "$POD" -- cilium bpf endpoint list 2>/dev/null >> "$TEMP_FILE" || true
done

echo ""
echo "Parsing endpoint statistics..."

# Parse the output and convert to JSON
python3 - "$TEMP_FILE" "$OUTPUT_FILE" <<'PYTHON'
import sys
import json
import re

input_file = sys.argv[1]
output_file = sys.argv[2]

metrics = {}

with open(input_file, 'r') as f:
    lines = f.readlines()
    
    # Skip header lines
    data_started = False
    for line in lines:
        line = line.strip()
        
        # Skip empty lines and headers
        if not line or line.startswith('ENDPOINT') or line.startswith('---'):
            continue
            
        # Parse endpoint data
        # Format: ENDPOINT_ID  FLAGS  IDENTITY  INGRESS_BYTES  EGRESS_BYTES  INGRESS_PKTS  EGRESS_PKTS  ...
        parts = line.split()
        if len(parts) < 7:
            continue
            
        try:
            endpoint_id = parts[0]
            
            # Try to extract byte/packet stats
            # The format varies, so we'll try to find numbers
            numbers = [int(p) for p in parts if p.isdigit()]
            
            if len(numbers) >= 4:
                # Assume: ingress_bytes, egress_bytes, ingress_packets, egress_packets
                ingress_bytes = numbers[0] if len(numbers) > 0 else 0
                egress_bytes = numbers[1] if len(numbers) > 1 else 0
                ingress_packets = numbers[2] if len(numbers) > 2 else 0
                egress_packets = numbers[3] if len(numbers) > 3 else 0
                
                metrics[f"endpoint_{endpoint_id}"] = {
                    "endpoint_id": endpoint_id,
                    "ingress_bytes": ingress_bytes,
                    "egress_bytes": egress_bytes,
                    "ingress_packets": ingress_packets,
                    "egress_packets": egress_packets,
                    "total_bytes": ingress_bytes + egress_bytes,
                    "total_packets": ingress_packets + egress_packets
                }
        except (ValueError, IndexError):
            continue

# Write JSON output
with open(output_file, 'w') as f:
    json.dump(metrics, f, indent=2, sort_keys=True)

print(f"Extracted metrics for {len(metrics)} endpoints")
PYTHON

# Generate summary
if [ -f "$OUTPUT_FILE" ]; then
    python3 - "$OUTPUT_FILE" "$SUMMARY_FILE" <<'PYTHON2'
import sys
import json

metrics_file = sys.argv[1]
summary_file = sys.argv[2]

with open(metrics_file, 'r') as f:
    metrics = json.load(f)

total_ingress = sum(m.get('ingress_bytes', 0) for m in metrics.values())
total_egress = sum(m.get('egress_bytes', 0) for m in metrics.values())
total_bytes = total_ingress + total_egress

total_ingress_pkts = sum(m.get('ingress_packets', 0) for m in metrics.values())
total_egress_pkts = sum(m.get('egress_packets', 0) for m in metrics.values())
total_packets = total_ingress_pkts + total_egress_pkts

with open(summary_file, 'w') as f:
    f.write("Cilium Byte/Packet Counter Summary\n")
    f.write("=" * 50 + "\n\n")
    f.write(f"Total endpoints:     {len(metrics)}\n")
    f.write(f"Total ingress bytes: {total_ingress:,}\n")
    f.write(f"Total egress bytes:  {total_egress:,}\n")
    f.write(f"Total bytes:         {total_bytes:,}\n")
    f.write(f"\n")
    f.write(f"Total ingress pkts:  {total_ingress_pkts:,}\n")
    f.write(f"Total egress pkts:   {total_egress_pkts:,}\n")
    f.write(f"Total packets:       {total_packets:,}\n")
    f.write(f"\n")
    f.write(f"Top 10 endpoints by total bytes:\n")
    f.write("-" * 50 + "\n")
    
    sorted_endpoints = sorted(
        metrics.items(),
        key=lambda x: x[1].get('total_bytes', 0),
        reverse=True
    )[:10]
    
    for endpoint, data in sorted_endpoints:
        f.write(f"{endpoint:20} {data.get('total_bytes', 0):>12,} bytes\n")

print(f"Summary written to {summary_file}")
PYTHON2
    
    cat "$SUMMARY_FILE"
fi

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "✓ Byte/packet metrics extracted to: $OUTPUT_FILE"
echo "✓ Summary written to: $SUMMARY_FILE"
