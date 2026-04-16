#!/bin/bash
# create-sample-data.sh
# Creates a sample dataset with configurable number of events for Git upload

set -e

# Default values
DEFAULT_SAMPLE_SIZE=1000
SAMPLE_SIZE=${1:-$DEFAULT_SAMPLE_SIZE}

echo "=== Creating Sample Data for Git Upload ==="
echo ""
echo "Sample size: $SAMPLE_SIZE events/flows per file"
echo ""

# Validate input
if ! [[ "$SAMPLE_SIZE" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Sample size must be a positive number"
    echo "Usage: $0 [sample_size]"
    echo "Example: $0 1000"
    exit 1
fi

# Check if data directory exists
if [ ! -d "data" ]; then
    echo "ERROR: No data directory found"
    echo "Run ./collection/export-all.sh first to collect test data"
    exit 1
fi

# Create sample directory
SAMPLE_DIR="data-sample"
echo "Step 1: Creating sample directory structure..."
rm -rf "$SAMPLE_DIR"  # Remove old samples
mkdir -p "$SAMPLE_DIR"/{hubble,packetbeat,metrics,cluster}
echo "  ✓ Directory created: $SAMPLE_DIR/"
echo ""

# Sample Hubble data
echo "Step 2: Sampling Hubble data..."
if [ -f "data/hubble/hubble-flows-all.json" ]; then
    head -n "$SAMPLE_SIZE" data/hubble/hubble-flows-all.json > "$SAMPLE_DIR/hubble/hubble-flows-all.json"
    ACTUAL_COUNT=$(wc -l < "$SAMPLE_DIR/hubble/hubble-flows-all.json")
    SIZE=$(du -h "$SAMPLE_DIR/hubble/hubble-flows-all.json" | cut -f1)
    echo "  ✓ hubble-flows-all.json: $ACTUAL_COUNT flows ($SIZE)"
else
    echo "  ⚠️  data/hubble/hubble-flows-all.json not found"
fi

if [ -f "data/hubble/hubble-flows-demo.json" ]; then
    head -n "$SAMPLE_SIZE" data/hubble/hubble-flows-demo.json > "$SAMPLE_DIR/hubble/hubble-flows-demo.json"
    ACTUAL_COUNT=$(wc -l < "$SAMPLE_DIR/hubble/hubble-flows-demo.json")
    SIZE=$(du -h "$SAMPLE_DIR/hubble/hubble-flows-demo.json" | cut -f1)
    echo "  ✓ hubble-flows-demo.json: $ACTUAL_COUNT flows ($SIZE)"
else
    echo "  ⚠️  data/hubble/hubble-flows-demo.json not found"
fi

if [ -f "data/hubble/hubble-flows-http.json" ]; then
    head -n "$SAMPLE_SIZE" data/hubble/hubble-flows-http.json > "$SAMPLE_DIR/hubble/hubble-flows-http.json"
    ACTUAL_COUNT=$(wc -l < "$SAMPLE_DIR/hubble/hubble-flows-http.json")
    SIZE=$(du -h "$SAMPLE_DIR/hubble/hubble-flows-http.json" | cut -f1)
    echo "  ✓ hubble-flows-http.json: $ACTUAL_COUNT flows ($SIZE)"
else
    echo "  ⚠️  data/hubble/hubble-flows-http.json not found"
fi

if [ -f "data/hubble/hubble-flows-dropped.json" ]; then
    head -n "$SAMPLE_SIZE" data/hubble/hubble-flows-dropped.json > "$SAMPLE_DIR/hubble/hubble-flows-dropped.json"
    ACTUAL_COUNT=$(wc -l < "$SAMPLE_DIR/hubble/hubble-flows-dropped.json")
    SIZE=$(du -h "$SAMPLE_DIR/hubble/hubble-flows-dropped.json" | cut -f1)
    echo "  ✓ hubble-flows-dropped.json: $ACTUAL_COUNT flows ($SIZE)"
else
    echo "  ⚠️  data/hubble/hubble-flows-dropped.json not found"
fi

if [ -f "data/hubble/hubble-flows-dns.json" ]; then
    head -n "$SAMPLE_SIZE" data/hubble/hubble-flows-dns.json > "$SAMPLE_DIR/hubble/hubble-flows-dns.json"
    ACTUAL_COUNT=$(wc -l < "$SAMPLE_DIR/hubble/hubble-flows-dns.json")
    SIZE=$(du -h "$SAMPLE_DIR/hubble/hubble-flows-dns.json" | cut -f1)
    echo "  ✓ hubble-flows-dns.json: $ACTUAL_COUNT flows ($SIZE)"
else
    echo "  ⚠️  data/hubble/hubble-flows-dns.json not found"
fi

echo ""

# Sample Packetbeat data
echo "Step 3: Sampling Packetbeat data..."
if [ -f "data/packetbeat/packetbeat-combined.json" ]; then
    head -n "$SAMPLE_SIZE" data/packetbeat/packetbeat-combined.json > "$SAMPLE_DIR/packetbeat/packetbeat-combined.json"
    ACTUAL_COUNT=$(wc -l < "$SAMPLE_DIR/packetbeat/packetbeat-combined.json")
    SIZE=$(du -h "$SAMPLE_DIR/packetbeat/packetbeat-combined.json" | cut -f1)
    echo "  ✓ packetbeat-combined.json: $ACTUAL_COUNT events ($SIZE)"
else
    echo "  ⚠️  data/packetbeat/packetbeat-combined.json not found"
fi

echo ""

# Copy stats files (already small)
echo "Step 4: Copying statistics files..."
if [ -f "data/hubble/hubble-stats.txt" ]; then
    cp data/hubble/hubble-stats.txt "$SAMPLE_DIR/hubble/"
    echo "  ✓ hubble-stats.txt"
fi

if [ -f "data/packetbeat/packetbeat-stats.txt" ]; then
    cp data/packetbeat/packetbeat-stats.txt "$SAMPLE_DIR/packetbeat/"
    echo "  ✓ packetbeat-stats.txt"
fi

if [ -f "data/hubble/cilium-status.txt" ]; then
    cp data/hubble/cilium-status.txt "$SAMPLE_DIR/hubble/"
    echo "  ✓ cilium-status.txt"
fi

echo ""

# Copy metrics and cluster info (already small)
echo "Step 5: Copying metadata..."
if [ -d "data/metrics" ]; then
    cp -r data/metrics/* "$SAMPLE_DIR/metrics/" 2>/dev/null || echo "  (no metrics files)"
    echo "  ✓ Metrics copied"
fi

if [ -d "data/cluster" ]; then
    cp -r data/cluster/* "$SAMPLE_DIR/cluster/" 2>/dev/null || echo "  (no cluster files)"
    echo "  ✓ Cluster info copied"
fi

echo ""

# Create README for sample data
echo "Step 6: Creating README..."
cat > "$SAMPLE_DIR/README.md" <<EOF
# Sample Test Data

This directory contains a sample of the full test dataset collected from the Cilium vs Packetbeat comparison.

## Sample Size

Each file contains the **first $SAMPLE_SIZE events/flows** from the original dataset.

## Original Dataset

- **Hubble flows:** 12,232 total flows
- **Packetbeat events:** 970,539 total events
- **Total size:** ~4 GB
- **Sample size:** $(du -sh "$SAMPLE_DIR" | cut -f1)

## Files Included

### Hubble Data (\`hubble/\`)
$(ls -lh "$SAMPLE_DIR/hubble/" 2>/dev/null | tail -n +2 | awk '{printf "- %s (%s)\n", $9, $5}')

### Packetbeat Data (\`packetbeat/\`)
$(ls -lh "$SAMPLE_DIR/packetbeat/" 2>/dev/null | tail -n +2 | awk '{printf "- %s (%s)\n", $9, $5}')

### Metadata
- \`metrics/\` - Resource usage snapshots
- \`cluster/\` - Cluster state information

## Using This Sample Data

### Quick Analysis

View HTTP status codes (Hubble):
\`\`\`bash
cat hubble/hubble-flows-http.json | jq -r '.l7.http.code' | sort | uniq -c
\`\`\`

View HTTP status codes (Packetbeat):
\`\`\`bash
cat packetbeat/packetbeat-combined.json | jq -r 'select(.type=="http") | .http.response.status_code' | sort | uniq -c
\`\`\`

View policy violations (Hubble):
\`\`\`bash
cat hubble/hubble-flows-dropped.json | jq -r '.drop_reason_desc' | sort | uniq -c
\`\`\`

### Running Analysis Scripts

The analysis scripts in \`testing/\` and \`analysis/\` will work with this sample data, though results will be based on only $SAMPLE_SIZE events instead of the full dataset.

## Regenerating Sample Data

To create a sample with a different size:

\`\`\`bash
# Create sample with 500 events
./create-sample-data.sh 500

# Create sample with 5000 events
./create-sample-data.sh 5000
\`\`\`

## Full Dataset

The complete 4 GB dataset is available:
- Via GitHub Releases (if uploaded)
- On request from repository owner
- By re-running the test: \`./testing/deploy-error-scenarios.sh\`

## Sample Limitations

This sample represents only **$(awk "BEGIN {printf \"%.1f\", ($SAMPLE_SIZE/970539)*100}")%** of the Packetbeat events and **$(awk "BEGIN {printf \"%.1f\", ($SAMPLE_SIZE/12232)*100}")%** of the Hubble flows. 

Patterns and statistics derived from this sample may not be representative of the full dataset, but the sample is sufficient for:
- Understanding data formats
- Testing analysis scripts
- Demonstrating tool capabilities
- Learning the workflow

For production decisions, analysis should be performed on complete datasets from your own environment.

---

**Sample generated:** $(date)  
**Test date:** February 5, 2026  
**Script:** \`create-sample-data.sh $SAMPLE_SIZE\`
EOF

echo "  ✓ README.md created"
echo ""

# Generate summary
TOTAL_SIZE=$(du -sh "$SAMPLE_DIR" | cut -f1)
FILE_COUNT=$(find "$SAMPLE_DIR" -type f | wc -l)

echo "=== Sample Data Created Successfully ==="
echo ""
echo "📂 Directory: $SAMPLE_DIR/"
echo "📊 Files: $FILE_COUNT"
echo "💾 Total size: $TOTAL_SIZE"
echo ""

# Show what was created
echo "Contents:"
tree "$SAMPLE_DIR" -h 2>/dev/null || find "$SAMPLE_DIR" -type f -exec ls -lh {} \; | awk '{printf "  %-70s %10s\n", $9, $5}'

echo ""
echo "=== Ready to Upload to Git ==="
echo ""
echo "This sample data is small enough to commit to Git:"
echo ""
echo "  git add $SAMPLE_DIR/"
echo "  git commit -m 'Add sample test data ($SAMPLE_SIZE events per file)'"
echo "  git push origin error_scenarios"
echo ""

# Check size and warn if too large
SIZE_BYTES=$(du -sb "$SAMPLE_DIR" | cut -f1)
SIZE_MB=$((SIZE_BYTES / 1048576))

if [ $SIZE_MB -gt 50 ]; then
    echo "⚠️  WARNING: Sample size is ${SIZE_MB}MB"
    echo "   Consider using a smaller sample size for Git:"
    echo "   ./create-sample-data.sh 500"
    echo ""
elif [ $SIZE_MB -gt 10 ]; then
    echo "ℹ️  Note: Sample size is ${SIZE_MB}MB (acceptable for Git, but not huge)"
    echo ""
else
    echo "✅ Sample size is ${SIZE_MB}MB (perfect for Git upload)"
    echo ""
fi

echo "To create a different sample size:"
echo "  ./create-sample-data.sh 500   # Smaller sample (~5-10 MB)"
echo "  ./create-sample-data.sh 5000  # Larger sample (~50-100 MB)"
