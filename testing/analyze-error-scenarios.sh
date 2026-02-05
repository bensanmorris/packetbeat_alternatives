#!/bin/bash
set -e

echo "=== Analyzing Error Scenario Results ==="
echo ""

if [ ! -d "data" ]; then
    echo "ERROR: No data directory found. Run ./collection/export-all.sh first"
    exit 1
fi

REPORT_FILE="reports/error-scenarios-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p reports

exec > >(tee "$REPORT_FILE")

cat <<'EOF'
================================================================================
              ERROR SCENARIO ANALYSIS: CILIUM/HUBBLE vs PACKETBEAT
================================================================================

EOF

echo "Generated: $(date)"
echo ""

cat <<'EOF'
================================================================================
1. HTTP ERROR DETECTION
================================================================================

EOF

echo "Hubble HTTP Status Codes:"
if [ -f "data/hubble/hubble-flows-all.json" ]; then
    echo "  Looking for HTTP responses with status codes..."
    cat data/hubble/hubble-flows-all.json | \
        jq -r 'select(.l7.http.code) | "\(.l7.http.method // "?") \(.l7.http.url // "?") -> \(.l7.http.code)"' 2>/dev/null | \
        sort | uniq -c | sort -rn || echo "  No HTTP status codes found (L7 visibility may not be enabled)"
    
    echo ""
    echo "  HTTP error count (4xx, 5xx):"
    ERROR_COUNT=$(cat data/hubble/hubble-flows-all.json | \
        jq -r 'select(.l7.http.code >= 400) | .l7.http.code' 2>/dev/null | wc -l || echo "0")
    echo "  Total HTTP errors: $ERROR_COUNT"
fi

echo ""
echo "Packetbeat HTTP Status Codes:"
if [ -f "data/packetbeat/packetbeat-combined.json" ]; then
    echo "  HTTP status code distribution:"
    cat data/packetbeat/packetbeat-combined.json | \
        jq -r 'select(.type=="http" and .http.response.status_code) | .http.response.status_code' 2>/dev/null | \
        sort | uniq -c | sort -rn | awk '{printf "    %s: %s requests\n", $2, $1}' || echo "  No HTTP data found"
    
    echo ""
    echo "  HTTP errors by type:"
    cat data/packetbeat/packetbeat-combined.json | \
        jq -r 'select(.type=="http" and .http.response.status_code >= 400) | 
               if .http.response.status_code >= 500 then "5xx Server Error"
               elif .http.response.status_code >= 400 then "4xx Client Error"
               else "Other" end' 2>/dev/null | \
        sort | uniq -c | sort -rn || echo "  No HTTP errors found"
fi

cat <<'EOF'

================================================================================
2. NETWORK POLICY VIOLATIONS (Cilium Advantage)
================================================================================

EOF

echo "Hubble Dropped Flows (Policy Violations):"
if [ -f "data/hubble/hubble-flows-all.json" ]; then
    POLICY_DROPS=$(cat data/hubble/hubble-flows-all.json | \
        jq -r 'select(.verdict=="DROPPED") | .drop_reason_desc // "POLICY_DENIED"' 2>/dev/null | wc -l || echo "0")
    echo "  Total policy-denied connections: $POLICY_DROPS"
    
    echo ""
    echo "  Drop reasons:"
    cat data/hubble/hubble-flows-all.json | \
        jq -r 'select(.verdict=="DROPPED") | .drop_reason_desc // "UNKNOWN"' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 | awk '{printf "    %-40s %s\n", $2, $1}' || echo "  No drops found"
    
    echo ""
    echo "  Dropped connections by source pod:"
    cat data/hubble/hubble-flows-all.json | \
        jq -r 'select(.verdict=="DROPPED") | .source.pod_name // .source.identity // "unknown"' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 | awk '{printf "    %-40s %s drops\n", $2, $1}' || echo "  No data"
    
    echo ""
    echo "  Dropped connections by destination:"
    cat data/hubble/hubble-flows-all.json | \
        jq -r 'select(.verdict=="DROPPED") | .destination.pod_name // .destination.identity // "unknown"' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 | awk '{printf "    %-40s %s drops\n", $2, $1}' || echo "  No data"
fi

echo ""
echo "Packetbeat Policy Detection:"
echo "  ⚠️  Packetbeat cannot distinguish network policy drops from other connection failures"
echo "  ⚠️  No Kubernetes policy context available"
echo "  It will only show: Connection refused/timeout without reason"

cat <<'EOF'

================================================================================
3. DNS FAILURE DETECTION
================================================================================

EOF

echo "Hubble DNS Queries:"
if [ -f "data/hubble/hubble-flows-all.json" ]; then
    echo "  DNS query results:"
    cat data/hubble/hubble-flows-all.json | \
        jq -r 'select(.l7.dns) | 
               "\(.l7.dns.query // "unknown") -> \(.l7.dns.rcode // .verdict)"' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 || echo "  No DNS data found"
    
    echo ""
    echo "  DNS failures (NXDOMAIN, SERVFAIL, etc):"
    FAILED_DNS=$(cat data/hubble/hubble-flows-all.json | \
        jq -r 'select(.l7.dns and (.l7.dns.rcode != 0 and .l7.dns.rcode != null)) | .l7.dns.query' 2>/dev/null | \
        wc -l || echo "0")
    echo "  Total failed DNS queries: $FAILED_DNS"
fi

echo ""
echo "Packetbeat DNS Queries:"
if [ -f "data/packetbeat/packetbeat-combined.json" ]; then
    echo "  DNS query results:"
    cat data/packetbeat/packetbeat-combined.json | \
        jq -r 'select(.type=="dns") | 
               "\(.dns.question.name // "unknown") -> \(.dns.response_code // "unknown")"' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 || echo "  No DNS data found"
fi

cat <<'EOF'

================================================================================
4. CONNECTION FAILURE TYPES
================================================================================

EOF

echo "Hubble Connection Failures:"
if [ -f "data/hubble/hubble-flows-all.json" ]; then
    echo "  Failed connections by type:"
    cat data/hubble/hubble-flows-all.json | \
        jq -r 'select(.verdict=="DROPPED" or .verdict=="ERROR") | 
               "\(.verdict): \(.drop_reason_desc // "Unknown reason")"' 2>/dev/null | \
        sort | uniq -c | sort -rn || echo "  No failures found"
fi

echo ""
echo "Packetbeat Connection Failures:"
if [ -f "data/packetbeat/packetbeat-combined.json" ]; then
    echo "  TCP connection states:"
    cat data/packetbeat/packetbeat-combined.json | \
        jq -r 'select(.type=="flow") | .flow.final // .status // "unknown"' 2>/dev/null | \
        sort | uniq -c | sort -rn || echo "  No flow data found"
fi

cat <<'EOF'

================================================================================
5. TIMEOUT vs REFUSED vs DROPPED
================================================================================

EOF

echo "Distinguishing failure types is critical for troubleshooting:"
echo ""
echo "Cilium/Hubble Detection:"
echo "  ✓ Policy Drop    - Clear verdict='DROPPED' with policy reason"
echo "  ✓ Connection Refused - TCP RST visible"
echo "  ✓ Timeout        - Connection attempt without response"
echo "  ✓ Context        - Shows which pod, which policy, which namespace"
echo ""
echo "Packetbeat Detection:"
echo "  ✓ Connection Refused - TCP RST visible"
echo "  ✓ Timeout        - No response seen"
echo "  ✗ Policy Drop    - Looks identical to timeout/refused, no context"
echo "  ✗ Context        - Only IP addresses, no Kubernetes identity"

cat <<'EOF'

================================================================================
6. SCENARIO-SPECIFIC FINDINGS
================================================================================

EOF

echo "Error Generator Activity:"
POD_NAME=$(kubectl get pod -n demo -l app=error-generator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
if [ "$POD_NAME" != "not-found" ]; then
    echo "  Recent error generator output:"
    kubectl logs -n demo "$POD_NAME" --tail=50 2>/dev/null | grep -E "(HTTP|TCP|DNS|TIMEOUT|POLICY)" | tail -20 || echo "  No logs available"
else
    echo "  Error generator pod not found"
fi

echo ""
echo "Policy Violator Activity:"
POD_NAME=$(kubectl get pod -n demo -l app=policy-violator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
if [ "$POD_NAME" != "not-found" ]; then
    echo "  Recent policy violation attempts:"
    kubectl logs -n demo "$POD_NAME" --tail=50 2>/dev/null | grep -E "(POLICY|Blocked|Connected)" | tail -20 || echo "  No logs available"
else
    echo "  Policy violator pod not found"
fi

cat <<'EOF'

================================================================================
7. RECOMMENDATIONS BY ERROR TYPE
================================================================================

EOF

cat <<'RECOMMENDATIONS'
Based on error scenario testing:

┌─────────────────────────────────┬──────────────────┬───────────────────┐
│ Error Type                      │ Cilium/Hubble    │ Packetbeat        │
├─────────────────────────────────┼──────────────────┼───────────────────┤
│ Network Policy Violations       │ ✓✓✓ EXCELLENT    │ ✗ Cannot detect   │
│ - Shows policy name & reason    │ Clear context    │ Just sees drop    │
│ - Pod identity preserved        │                  │                   │
├─────────────────────────────────┼──────────────────┼───────────────────┤
│ HTTP 4xx/5xx Errors             │ ✓✓ Good with L7  │ ✓✓✓ Excellent     │
│ - Requires L7 visibility        │ Need to enable   │ Always captured   │
│ - Pod context included          │                  │ More detail       │
├─────────────────────────────────┼──────────────────┼───────────────────┤
│ DNS Failures (NXDOMAIN)         │ ✓✓✓ Excellent    │ ✓✓✓ Excellent     │
│ - Both capture well             │                  │                   │
├─────────────────────────────────┼──────────────────┼───────────────────┤
│ Connection Refused              │ ✓✓ Good          │ ✓✓ Good           │
│ - Both see TCP RST              │                  │                   │
├─────────────────────────────────┼──────────────────┼───────────────────┤
│ Timeouts                        │ ✓ Basic          │ ✓✓ Better timing  │
│ - Flow-level only               │ Less detail      │ Packet-level      │
├─────────────────────────────────┼──────────────────┼───────────────────┤
│ TLS Handshake Failures          │ ✓ Basic          │ ✓✓✓ Excellent     │
│ - Sees failure                  │ Less detail      │ Full TLS context  │
└─────────────────────────────────┴──────────────────┴───────────────────┘

CRITICAL INSIGHT:
In Kubernetes environments, the #1 source of connection failures is often
Network Policies, not application errors. Cilium's ability to show:
  - WHICH policy blocked the connection
  - WHICH pod tried to connect
  - WHICH pod was the target
  - WHY it was blocked

...makes it dramatically more useful for troubleshooting than Packetbeat's
"connection refused/timeout" without context.

RECOMMENDATIONS:
1. Use Cilium/Hubble as PRIMARY monitoring tool in Kubernetes
2. Keep Packetbeat for:
   - Deep HTTP/TLS forensics when needed
   - Compliance requirements for packet-level detail
   - Non-Kubernetes environments
3. Enable Hubble L7 visibility for HTTP error detection
4. Use Cilium's policy editor to test before deploying policies

RECOMMENDATIONS

cat <<'EOF'

================================================================================
Report Complete
================================================================================

EOF

echo ""
echo "Report saved to: $REPORT_FILE"
echo ""
echo "Next steps:"
echo "  1. Review policy violation sections above"
echo "  2. Enable Hubble L7 visibility if HTTP errors important"
echo "  3. Run longer test (2-24 hours) for more data"
echo "  4. Compare storage costs of extended run"
