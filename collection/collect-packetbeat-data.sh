#!/bin/bash
set -e

echo "=== Collecting Packetbeat Data ==="
echo ""

# Create data directory
DATA_DIR="data/packetbeat"
mkdir -p "$DATA_DIR"

echo "Step 1: Getting Packetbeat pod names..."
PACKETBEAT_PODS=$(kubectl get pods -n monitoring -l app=packetbeat -o jsonpath='{.items[*].metadata.name}')

if [ -z "$PACKETBEAT_PODS" ]; then
    echo "ERROR: No Packetbeat pods found"
    echo "Make sure Packetbeat is deployed: kubectl apply -f deploy/packetbeat-daemonset.yaml"
    exit 1
fi

echo "Found Packetbeat pods: $PACKETBEAT_PODS"
echo ""

echo "Step 2: Collecting Packetbeat logs..."
for pod in $PACKETBEAT_PODS; do
    echo "  Collecting logs from $pod..."
    kubectl logs -n monitoring $pod --tail=10000 > "$DATA_DIR/logs-${pod}.txt" 2>&1 || true
done

echo ""
echo "Step 3: Extracting capture files from Packetbeat pods..."

# Extract directly from pods instead of Kind nodes
for pod in $PACKETBEAT_PODS; do
    echo "  Extracting captures from $pod..."
    
    # Create pod-specific directory
    POD_DIR="$DATA_DIR/$pod"
    mkdir -p "$POD_DIR"
    
    # Copy capture files from the pod's /captures directory
    if kubectl exec -n monitoring "$pod" -- test -d /captures 2>/dev/null; then
        # Use kubectl cp to copy the entire directory
        kubectl cp "monitoring/$pod:/captures" "$POD_DIR/captures" 2>/dev/null || {
            echo "    ⚠️  Could not copy captures from $pod using kubectl cp"
            echo "    Trying tar method..."
            
            # Alternative: use tar over kubectl exec
            kubectl exec -n monitoring "$pod" -- tar czf - /captures 2>/dev/null | \
                tar xzf - -C "$POD_DIR" --strip-components=1 2>/dev/null || {
                echo "    ⚠️  Could not extract captures from $pod"
            }
        }
    else
        echo "    ⚠️  No /captures directory found in $pod"
    fi
done

echo ""
echo "Step 4: Combining JSON capture data..."
# Combine all .ndjson files from all pods
COMBINED_FILE="$DATA_DIR/packetbeat-combined.json"
> "$COMBINED_FILE"  # Create empty file

# Find all ndjson files and concatenate them
find "$DATA_DIR" -name "*.ndjson" -type f 2>/dev/null | while read -r file; do
    echo "  Processing $file..."
    cat "$file" >> "$COMBINED_FILE" 2>/dev/null || true
done

# Count lines in combined file
LINE_COUNT=$(wc -l < "$COMBINED_FILE" 2>/dev/null || echo "0")
echo "  Combined $LINE_COUNT events into $COMBINED_FILE"

echo ""
echo "Step 5: Generating Packetbeat statistics..."
if [ -s "$COMBINED_FILE" ]; then
    cat > "$DATA_DIR/packetbeat-stats.txt" <<EOF
Packetbeat Statistics
=====================

Total events: $LINE_COUNT

File size: $(du -h "$COMBINED_FILE" | cut -f1)

Event types (sample):
$(head -100 "$COMBINED_FILE" | jq -r '.type // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn || echo "  (jq parsing failed)")

Protocols (sample):
$(head -100 "$COMBINED_FILE" | jq -r '.network.protocol // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn || echo "  (jq parsing failed)")

Top source IPs (sample):
$(head -100 "$COMBINED_FILE" | jq -r '.source.ip // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn | head -10 || echo "  (jq parsing failed)")

Raw files location:
EOF

    # List all captured files
    find "$DATA_DIR" -name "*.ndjson" -type f -exec ls -lh {} \; >> "$DATA_DIR/packetbeat-stats.txt"
    
    echo "  ✓ Statistics generated"
else
    echo "  ⚠️  No capture data found"
fi

echo ""
echo "=== Packetbeat Data Collection Complete ==="
echo ""
echo "Data saved to: $DATA_DIR/"
du -sh "$DATA_DIR"
echo ""
echo "Files collected:"
find "$DATA_DIR" -type f -exec ls -lh {} \; | head -20
