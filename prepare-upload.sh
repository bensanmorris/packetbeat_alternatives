#!/bin/bash
# prepare-upload.sh
# Prepares test results for uploading to GitHub repository

set -e

echo "=== Preparing Test Results for Git Upload ==="
echo ""

# Check if we're in the right directory
if [ ! -f "README.md" ]; then
    echo "ERROR: Please run this from the packetbeat_alternatives directory"
    exit 1
fi

# Check if data exists
if [ ! -d "data" ]; then
    echo "ERROR: No data directory found"
    echo "Run ./collection/export-all.sh first to collect test data"
    exit 1
fi

# Check data size
DATA_SIZE=$(du -sh data/ 2>/dev/null | cut -f1)
HUBBLE_SIZE=$(du -sh data/hubble/*.json 2>/dev/null | tail -1 | cut -f1 || echo "0")
PACKETBEAT_SIZE=$(du -sh data/packetbeat/*.json 2>/dev/null | tail -1 | cut -f1 || echo "0")

echo "Current data sizes:"
echo "  Total:       $DATA_SIZE"
echo "  Hubble JSON: $HUBBLE_SIZE"
echo "  Packetbeat:  $PACKETBEAT_SIZE"
echo ""

# Create upload package directory
UPLOAD_DIR="upload-package-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$UPLOAD_DIR"

echo "Step 1: Creating summary package..."
# Copy small summary files
cp data/SUMMARY.txt "$UPLOAD_DIR/" 2>/dev/null || echo "  (no SUMMARY.txt)"
cp data/hubble/hubble-stats.txt "$UPLOAD_DIR/hubble-stats.txt" 2>/dev/null || echo "  (no hubble-stats.txt)"
cp data/packetbeat/packetbeat-stats.txt "$UPLOAD_DIR/packetbeat-stats.txt" 2>/dev/null || echo "  (no packetbeat-stats.txt)"

# Copy metrics directory
if [ -d "data/metrics" ]; then
    cp -r data/metrics "$UPLOAD_DIR/"
fi

# Copy cluster info
if [ -d "data/cluster" ]; then
    cp -r data/cluster "$UPLOAD_DIR/"
fi

echo "  ✓ Summary files copied"
echo ""

echo "Step 2: Copying analysis reports..."
if [ -d "reports" ]; then
    cp -r reports "$UPLOAD_DIR/"
    echo "  ✓ Reports copied"
else
    echo "  ⚠️  No reports directory (run ./testing/analyze-error-scenarios.sh)"
fi
echo ""

echo "Step 3: Creating sample data (1000 events)..."
mkdir -p "$UPLOAD_DIR/sample-data/hubble"
mkdir -p "$UPLOAD_DIR/sample-data/packetbeat"

# Sample Hubble flows
if [ -f "data/hubble/hubble-flows-all.json" ]; then
    head -1000 data/hubble/hubble-flows-all.json > "$UPLOAD_DIR/sample-data/hubble/hubble-flows-all.json"
    echo "  ✓ Hubble flows sampled"
fi

if [ -f "data/hubble/hubble-flows-http.json" ]; then
    head -1000 data/hubble/hubble-flows-http.json > "$UPLOAD_DIR/sample-data/hubble/hubble-flows-http.json"
    echo "  ✓ Hubble HTTP flows sampled"
fi

if [ -f "data/hubble/hubble-flows-dropped.json" ]; then
    head -1000 data/hubble/hubble-flows-dropped.json > "$UPLOAD_DIR/sample-data/hubble/hubble-flows-dropped.json"
    echo "  ✓ Hubble dropped flows sampled"
fi

# Sample Packetbeat data
if [ -f "data/packetbeat/packetbeat-combined.json" ]; then
    head -1000 data/packetbeat/packetbeat-combined.json > "$UPLOAD_DIR/sample-data/packetbeat/packetbeat-combined.json"
    echo "  ✓ Packetbeat data sampled"
fi
echo ""

echo "Step 4: Creating README for upload package..."
cat > "$UPLOAD_DIR/README.md" <<EOF
# Test Results Package

**Generated:** $(date)
**Test Duration:** See SUMMARY.txt for details

## Contents

- \`SUMMARY.txt\` - Overview of test run and data collected
- \`hubble-stats.txt\` - Cilium/Hubble flow statistics
- \`packetbeat-stats.txt\` - Packetbeat event statistics
- \`reports/\` - Analysis reports comparing both tools
- \`metrics/\` - Resource usage data
- \`cluster/\` - Cluster state snapshots
- \`sample-data/\` - Sample flows (1000 events each)

## Full Data

The complete raw data is NOT included in this package (too large for Git).

**Original data size:** $DATA_SIZE

To access full test data:
1. Check GitHub Releases for archived data
2. Or re-run the tests: \`./testing/deploy-error-scenarios.sh\`

## Using This Data

View the analysis report:
\`\`\`bash
cat reports/error-scenarios-*.txt | less
\`\`\`

Analyze sample data:
\`\`\`bash
# Hubble HTTP status codes
cat sample-data/hubble/hubble-flows-http.json | jq -r '.l7.http.code' | sort | uniq -c

# Packetbeat HTTP status codes  
cat sample-data/packetbeat/packetbeat-combined.json | jq -r 'select(.type=="http") | .http.response.status_code' | sort | uniq -c
\`\`\`
EOF

echo "  ✓ README created"
echo ""

# Check package size
PACKAGE_SIZE=$(du -sh "$UPLOAD_DIR" | cut -f1)
echo "Step 5: Upload package ready!"
echo "  Package: $UPLOAD_DIR/"
echo "  Size: $PACKAGE_SIZE"
echo ""

# Create compressed archive for GitHub Release
ARCHIVE_NAME="test-results-$(date +%Y%m%d-%H%M%S).tar.gz"
echo "Step 6: Creating archive for GitHub Release..."
tar czf "$ARCHIVE_NAME" "$UPLOAD_DIR"/
ARCHIVE_SIZE=$(ls -lh "$ARCHIVE_NAME" | awk '{print $5}')
echo "  ✓ Archive created: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
echo ""

# Create full data archive (if user wants to upload to Release)
echo "Step 7: Creating FULL data archive (optional)..."
FULL_ARCHIVE="full-test-data-$(date +%Y%m%d-%H%M%S).tar.gz"
tar czf "$FULL_ARCHIVE" data/
FULL_SIZE=$(ls -lh "$FULL_ARCHIVE" | awk '{print $5}')
echo "  ✓ Full data archive created: $FULL_ARCHIVE ($FULL_SIZE)"
echo ""

echo "=== Preparation Complete ==="
echo ""
echo "What to upload:"
echo ""
echo "1. RECOMMENDED - Upload summary package to Git:"
echo "   git add $UPLOAD_DIR/"
echo "   git commit -m 'Add test results from $(date +%Y-%m-%d)'"
echo "   git push origin error_scenarios"
echo "   (Size: $PACKAGE_SIZE - small enough for Git)"
echo ""
echo "2. OPTIONAL - Create GitHub Release with full data:"
echo "   - Go to: https://github.com/bensanmorris/packetbeat_alternatives/releases"
echo "   - Create new release"
echo "   - Upload: $FULL_ARCHIVE ($FULL_SIZE)"
echo "   - Or: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
echo ""
echo "3. OPTIONAL - Upload to external storage:"
echo "   - Google Drive / Dropbox / S3"
echo "   - Upload: $FULL_ARCHIVE"
echo "   - Share link in repository"
echo ""

# Check if we should warn about large files
if [ -d ".git" ]; then
    echo "Checking for large files in staging area..."
    LARGE_FILES=$(git ls-files --stage 2>/dev/null | awk '$3 > 52428800 {print $4}')
    if [ ! -z "$LARGE_FILES" ]; then
        echo ""
        echo "⚠️  WARNING: Large files detected in git (> 50 MB):"
        echo "$LARGE_FILES"
        echo ""
        echo "Consider:"
        echo "  1. git rm --cached <file>  # Remove from staging"
        echo "  2. Add to .gitignore"
        echo "  3. Use GitHub Release or Git LFS instead"
    fi
fi

echo ""
echo "Files created:"
echo "  📦 $UPLOAD_DIR/      (summary package for Git)"
echo "  📦 $ARCHIVE_NAME     (compressed summary)"
echo "  📦 $FULL_ARCHIVE     (full data for Release)"
echo ""
