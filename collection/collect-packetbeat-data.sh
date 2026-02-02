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
echo "Step 3: Extracting capture files from Kind nodes..."

# Get Kind nodes
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $NODES; do
    echo "  Extracting from node: $node..."
    
    # The node name in Kind corresponds to a Podman container
    CONTAINER_NAME="cilium-poc-${node}"
    
    # Create node-specific directory
    NODE_DIR="$DATA_DIR/$node"
    mkdir -p "$NODE_DIR"
    
    # Copy capture files from the container
    if podman exec "$CONTAINER_NAME" test -d /var/log/packetbeat-captures 2>/dev/null; then
        podman exec "$CONTAINER_NAME" tar czf - /var/log/packetbeat-captures 2>/dev/null | \
            tar xzf - -C "$NODE_DIR" --strip-components=3 2>/dev/null || {
            echo "    ⚠️  Could not extract captures from $node"
        }
    else
        echo "    ⚠️  No captures directory found on $node"
    fi
    
    # Also get the logs from the container
    if podman exec "$CONTAINER_NAME" test -d /var/log/packetbeat 2>/dev/null; then
        podman exec "$CONTAINER_NAME" tar czf - /var/log/packetbeat 2>/dev/null | \
            tar xzf - -C "$NODE_DIR" --strip-components=3 2>/dev/null || true
    fi
done

echo ""
echo "Step 4: Combining JSON capture data..."
# Combine all JSON files
find "$DATA_DIR" -name "packetbeat*" -type f -print0 2>/dev/null | \
    while IFS= read -r -d '' file; do
        cat "$file" 2>/dev/null
    done | jq -s '.' > "$DATA_DIR/packetbeat-combined.json" 2>/dev/null || {
    echo "  ⚠️  Could not combine JSON data"
    echo "  Raw files are still available in $DATA_DIR"
}

echo ""
echo "Step 5: Generating Packetbeat statistics..."
if [ -f "$DATA_DIR/packetbeat-combined.json" ]; then
    cat > "$DATA_DIR/packetbeat-stats.txt" <<EOF
Packetbeat Statistics
=====================

Total events: $(cat "$DATA_DIR/packetbeat-combined.json" | jq 'length' 2>/dev/null || echo "0")

Event types:
$(cat "$DATA_DIR/packetbeat-combined.json" | jq -r '.[] | .type // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn)

Protocols:
$(cat "$DATA_DIR/packetbeat-combined.json" | jq -r '.[] | .network.protocol // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn)

Status codes (HTTP):
$(cat "$DATA_DIR/packetbeat-combined.json" | jq -r '.[] | select(.type=="http") | .http.response.status_code // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn)

Top source IPs:
$(cat "$DATA_DIR/packetbeat-combined.json" | jq -r '.[] | .source.ip // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn | head -10)

Top destination IPs:
$(cat "$DATA_DIR/packetbeat-combined.json" | jq -r '.[] | .destination.ip // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn | head -10)
EOF
    echo "  ✓ Statistics generated"
else
    echo "  ⚠️  No combined JSON data available for statistics"
fi

echo ""
echo "=== Packetbeat Data Collection Complete ==="
echo ""
echo "Data saved to: $DATA_DIR/"
du -sh "$DATA_DIR"
echo ""
echo "Files collected:"
find "$DATA_DIR" -type f -exec ls -lh {} \; | head -20
