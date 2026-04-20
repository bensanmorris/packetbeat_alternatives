#!/bin/bash
set -e

# Extract byte/packet counters from Cilium endpoints
# Uses 'cilium endpoint get' text output to retrieve per-endpoint statistics

OUTPUT_FILE="${1:-data/hubble/cilium-byte-metrics.json}"
SUMMARY_FILE="${2:-data/hubble/byte-metrics-summary.txt}"

echo "=== Extracting Cilium Byte/Packet Counters from Endpoints ==="
echo ""

# Create output directory
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Get list of Cilium pods
CILIUM_PODS=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[*].metadata.name}')

echo "Collecting endpoint statistics from Cilium pods..."
echo ""

# Create temporary file for raw data
TEMP_FILE=$(mktemp)

# Collect endpoint IDs from first Cilium pod
FIRST_POD=$(echo $CILIUM_PODS | awk '{print $1}')
echo "  Getting endpoint list from $FIRST_POD..."

# Get endpoints with their details (namespace, pod name)
kubectl exec -n kube-system "$FIRST_POD" -- cilium endpoint list -o jsonpath='{range .items[*]}{.id}|{.status.external-identifiers.k8s-namespace}|{.status.external-identifiers.k8s-pod-name}{"\n"}{end}' 2>/dev/null > "$TEMP_FILE.endpoints"

if [ ! -s "$TEMP_FILE.endpoints" ]; then
    echo "  ⚠️  No endpoints found"
    echo "{}" > "$OUTPUT_FILE"
    exit 0
fi

echo "  Found $(wc -l < "$TEMP_FILE.endpoints") endpoints"
echo ""

# For each endpoint, get stats table
while IFS='|' read -r ENDPOINT_ID NAMESPACE POD_NAME; do
    if [ -z "$ENDPOINT_ID" ]; then
        continue
    fi
    
    echo "  Collecting stats for endpoint $ENDPOINT_ID ($NAMESPACE/$POD_NAME)..."
    
    # Get the stats table (appears after the JSON output)
    kubectl exec -n kube-system "$FIRST_POD" -- cilium endpoint get "$ENDPOINT_ID" 2>&1 | \
        awk '/REASON.*DIRECTION.*PACKETS.*BYTES/,/^$/' | \
        sed "s/^/$ENDPOINT_ID|$NAMESPACE|$POD_NAME|/" >> "$TEMP_FILE" || true
        
done < "$TEMP_FILE.endpoints"

echo ""
echo "Parsing endpoint statistics..."

# Parse the output and convert to JSON
python3 - "$TEMP_FILE" "$OUTPUT_FILE" <<'PYTHON'
import sys
import re

input_file = sys.argv[1]
output_file = sys.argv[2]

metrics = {}

with open(input_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line or 'REASON' in line or 'FILE' in line:
            continue
            
        # Format: ENDPOINT_ID|NAMESPACE|POD_NAME|REASON DIRECTION PACKETS BYTES ...
        parts = line.split('|')
        if len(parts) < 4:
            continue
            
        endpoint_id = parts[0].strip()
        namespace = parts[1].strip()
        pod_name = parts[2].strip()
        stats_line = parts[3].strip()
        
        # Parse stats line
        stats_parts = stats_line.split()
        if len(stats_parts) < 4:
            continue
            
        try:
            direction = stats_parts[1]  # INGRESS or EGRESS
            packets = int(stats_parts[2])
            bytes_val = int(stats_parts[3])
            
            # Create key
            key = f"{namespace}/{pod_name}" if namespace and pod_name else f"endpoint_{endpoint_id}"
            
            # Initialize if needed
            if key not in metrics:
                metrics[key] = {
                    "endpoint_id": endpoint_id,
                    "namespace": namespace,
                    "pod_name": pod_name,
                    "ingress_bytes": 0,
                    "egress_bytes": 0,
                    "ingress_packets": 0,
                    "egress_packets": 0
                }
            
            # Aggregate stats
            if direction == "INGRESS":
                metrics[key]["ingress_bytes"] += bytes_val
                metrics[key]["ingress_packets"] += packets
            elif direction == "EGRESS":
                metrics[key]["egress_bytes"] += bytes_val
                metrics[key]["egress_packets"] += packets
                
        except (ValueError, IndexError):
            continue

# Add totals
for key in metrics:
    metrics[key]["total_bytes"] = metrics[key]["ingress_bytes"] + metrics[key]["egress_bytes"]
    metrics[key]["total_packets"] = metrics[key]["ingress_packets"] + metrics[key]["egress_packets"]

# Write JSON output
import json
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
        f.write(f"{endpoint:30} {data.get('total_bytes', 0):>12,} bytes\n")

print(f"Summary written to {summary_file}")
PYTHON2
    
    cat "$SUMMARY_FILE"
fi

# Cleanup
rm -f "$TEMP_FILE" "$TEMP_FILE.endpoints"

echo ""
echo "✓ Byte/packet metrics extracted to: $OUTPUT_FILE"
echo "✓ Summary written to: $SUMMARY_FILE"
