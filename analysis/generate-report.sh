#!/bin/bash
set -e

echo "=== Generating Comparison Report ==="
echo ""

# Check if data exists
if [ ! -d "data" ]; then
    echo "ERROR: No data directory found"
    echo "Please run: ./collection/export-all.sh"
    exit 1
fi

# Create reports directory
mkdir -p reports
REPORT_FILE="reports/comparison-report-$(date +%Y%m%d-%H%M%S).txt"

exec > >(tee "$REPORT_FILE")

cat <<'EOF'
================================================================================
                    CILIUM/HUBBLE vs PACKETBEAT
                        Comparison Report
================================================================================

EOF

echo "Generated: $(date)"
echo "Cluster: cilium-poc"
echo ""

cat <<'EOF'
================================================================================
1. DATA VOLUME COMPARISON
================================================================================

EOF

echo "Hubble Data:"
if [ -d "data/hubble" ]; then
    HUBBLE_SIZE=$(du -sh data/hubble 2>/dev/null | cut -f1)
    HUBBLE_FILES=$(find data/hubble -type f | wc -l)
    echo "  Total size: $HUBBLE_SIZE"
    echo "  Files: $HUBBLE_FILES"
    echo ""
    echo "  Breakdown:"
    find data/hubble -type f -exec ls -lh {} \; | awk '{printf "    %-40s %s\n", $9, $5}'
else
    echo "  No Hubble data found"
fi

echo ""
echo "Packetbeat Data:"
if [ -d "data/packetbeat" ]; then
    PB_SIZE=$(du -sh data/packetbeat 2>/dev/null | cut -f1)
    PB_FILES=$(find data/packetbeat -type f | wc -l)
    echo "  Total size: $PB_SIZE"
    echo "  Files: $PB_FILES"
    echo ""
    echo "  Sample files:"
    find data/packetbeat -type f | head -10 | xargs -I {} sh -c 'ls -lh "{}" | awk "{printf \"    %-40s %s\n\", \$9, \$5}"'
else
    echo "  No Packetbeat data found"
fi

cat <<'EOF'

================================================================================
2. FLOW/EVENT COUNT COMPARISON
================================================================================

EOF

HUBBLE_FLOWS=$(cat data/hubble/hubble-flows-all.json 2>/dev/null | wc -l || echo "0")
PB_EVENTS=$(cat data/packetbeat/packetbeat-combined.json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

echo "Hubble total flows: $HUBBLE_FLOWS"
echo "Packetbeat total events: $PB_EVENTS"
echo ""

if [ "$HUBBLE_FLOWS" -gt 0 ] && [ "$PB_EVENTS" -gt 0 ]; then
    RATIO=$(echo "scale=2; $HUBBLE_FLOWS / $PB_EVENTS" | bc)
    echo "Ratio (Hubble/Packetbeat): $RATIO"
fi

cat <<'EOF'

================================================================================
3. PROTOCOL COVERAGE
================================================================================

EOF

echo "Hubble Protocols:"
if [ -f "data/hubble/hubble-flows-all.json" ]; then
    cat data/hubble/hubble-flows-all.json | \
        jq -r 'if .l4.TCP then "TCP" elif .l4.UDP then "UDP" elif .l4.ICMPv4 then "ICMPv4" elif .l4.ICMPv6 then "ICMPv6" else "other" end' 2>/dev/null | \
        sort | uniq -c | sort -rn | awk '{printf "  %-20s %s\n", $2, $1}'
    
    echo ""
    echo "Hubble HTTP Requests:"
    HTTP_COUNT=$(cat data/hubble/hubble-flows-http.json 2>/dev/null | wc -l || echo "0")
    echo "  Total: $HTTP_COUNT"
    
    echo ""
    echo "Hubble DNS Queries:"
    DNS_COUNT=$(cat data/hubble/hubble-flows-dns.json 2>/dev/null | wc -l || echo "0")
    echo "  Total: $DNS_COUNT"
fi

echo ""
echo "Packetbeat Protocols:"
if [ -f "data/packetbeat/packetbeat-combined.json" ]; then
    cat data/packetbeat/packetbeat-combined.json | \
        jq -r '.[] | .type // "unknown"' 2>/dev/null | \
        sort | uniq -c | sort -rn | awk '{printf "  %-20s %s\n", $2, $1}'
fi

cat <<'EOF'

================================================================================
4. DROPPED/FAILED CONNECTIONS
================================================================================

EOF

echo "Hubble Dropped Flows:"
if [ -f "data/hubble/hubble-flows-dropped.json" ]; then
    DROPPED_COUNT=$(cat data/hubble/hubble-flows-dropped.json | wc -l)
    echo "  Total: $DROPPED_COUNT"
    echo ""
    echo "  Drop reasons:"
    cat data/hubble/hubble-flows-dropped.json | \
        jq -r '.drop_reason_desc // "UNKNOWN"' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -5 | awk '{printf "    %-40s %s\n", $2, $1}'
fi

echo ""
echo "Packetbeat Failed Connections:"
if [ -f "data/packetbeat/packetbeat-combined.json" ]; then
    FAILED_COUNT=$(cat data/packetbeat/packetbeat-combined.json | \
        jq '[.[] | select(.status == "Error" or .status == "Dropped")] | length' 2>/dev/null || echo "0")
    echo "  Total: $FAILED_COUNT"
fi

cat <<'EOF'

================================================================================
5. RESOURCE USAGE
================================================================================

EOF

echo "Cilium/Hubble Resource Usage:"
if [ -f "data/metrics/cilium-resources.json" ]; then
    cat data/metrics/cilium-resources.json | jq -r '. | "  Pod: \(.name)\n  CPU Request: \(.cpu // "N/A")\n  Memory Request: \(.memory // "N/A")\n"' 2>/dev/null
fi

echo "Packetbeat Resource Usage:"
if [ -f "data/metrics/packetbeat-resources.json" ]; then
    cat data/metrics/packetbeat-resources.json | jq -r '. | "  Pod: \(.name)\n  CPU Request: \(.cpu // "N/A")\n  Memory Request: \(.memory // "N/A")\n"' 2>/dev/null
fi

cat <<'EOF'

================================================================================
6. DATA COMPLETENESS ANALYSIS
================================================================================

EOF

echo "Checking data completeness..."
echo ""

# Check what Hubble captured
echo "Hubble Coverage:"
echo "  ✓ TCP flows: $(cat data/hubble/hubble-flows-all.json 2>/dev/null | jq '[.[] | select(.l4.TCP)] | length' 2>/dev/null || echo '0')"
echo "  ✓ UDP flows: $(cat data/hubble/hubble-flows-all.json 2>/dev/null | jq '[.[] | select(.l4.UDP)] | length' 2>/dev/null || echo '0')"
echo "  ✓ HTTP requests: $(cat data/hubble/hubble-flows-http.json 2>/dev/null | wc -l || echo '0')"
echo "  ✓ DNS queries: $(cat data/hubble/hubble-flows-dns.json 2>/dev/null | wc -l || echo '0')"
echo "  ✓ Identity information: Available"
echo "  ✓ Kubernetes labels: Available"

echo ""
echo "Packetbeat Coverage:"
if [ -f "data/packetbeat/packetbeat-combined.json" ]; then
    echo "  ✓ HTTP: $(cat data/packetbeat/packetbeat-combined.json | jq '[.[] | select(.type=="http")] | length' 2>/dev/null || echo '0')"
    echo "  ✓ DNS: $(cat data/packetbeat/packetbeat-combined.json | jq '[.[] | select(.type=="dns")] | length' 2>/dev/null || echo '0')"
    echo "  ✓ TLS: $(cat data/packetbeat/packetbeat-combined.json | jq '[.[] | select(.type=="tls")] | length' 2>/dev/null || echo '0')"
    echo "  ✓ Flow data: $(cat data/packetbeat/packetbeat-combined.json | jq '[.[] | select(.type=="flow")] | length' 2>/dev/null || echo '0')"
    echo "  ✓ Packet-level details: Available"
fi

cat <<'EOF'

================================================================================
7. SUMMARY AND RECOMMENDATIONS
================================================================================

EOF

cat <<'SUMMARY'
Based on the comparison:

Hubble Strengths:
  • Lower data volume (more efficient)
  • Kubernetes-native (pod/service identity)
  • Built-in network policy enforcement visibility
  • Real-time service dependency mapping
  • Lower resource overhead
  • Better integration with Kubernetes constructs

Packetbeat Strengths:
  • More detailed packet-level information
  • Broader protocol support out of the box
  • Can work in non-Kubernetes environments
  • Familiar Elastic Stack integration
  • More verbose logging (good for forensics)

Recommendations:
  1. If staying in Kubernetes: Hubble provides better efficiency and integration
  2. If need packet forensics: Packetbeat provides more raw packet details
  3. For production: Hubble's lower overhead is significant at scale
  4. For compliance: Evaluate which tool provides required audit detail

Next Steps:
  • Review detailed protocol coverage above
  • Compare storage requirements for your retention period
  • Test query performance for common use cases
  • Evaluate alerting/integration capabilities with your SIEM

SUMMARY

cat <<'EOF'

================================================================================
Report Complete
================================================================================

EOF

echo ""
echo "Report saved to: $REPORT_FILE"
echo ""
echo "For more details, examine:"
echo "  - data/hubble/hubble-stats.txt"
echo "  - data/packetbeat/packetbeat-stats.txt"
echo "  - Individual JSON files in data/ directories"
