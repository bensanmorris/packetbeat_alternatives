#!/bin/bash
set -e

echo "=== Exporting All POC Data ==="
echo ""

# Create base data directory
mkdir -p data
cd "$(dirname "$0")/.."

# Collect Hubble data
echo "1. Collecting Hubble data..."
./collection/collect-hubble-data.sh

echo ""
echo "2. Collecting Packetbeat data..."
./collection/collect-packetbeat-data.sh

echo ""
echo "3. Collecting resource usage metrics..."
mkdir -p data/metrics

# CPU and Memory usage
kubectl top pods --all-namespaces > data/metrics/pod-resources.txt 2>&1 || {
    echo "  ⚠️  Metrics server may not be available"
    echo "  This is OK - we'll use other methods"
}

# Cilium agent resource usage
kubectl get pods -n kube-system -l k8s-app=cilium -o json | \
    jq '.items[] | {name: .metadata.name, cpu: .spec.containers[0].resources.requests.cpu, memory: .spec.containers[0].resources.requests.memory}' \
    > data/metrics/cilium-resources.json 2>/dev/null || true

# Packetbeat resource usage
kubectl get pods -n monitoring -l app=packetbeat -o json | \
    jq '.items[] | {name: .metadata.name, cpu: .spec.containers[0].resources.requests.cpu, memory: .spec.containers[0].resources.requests.memory}' \
    > data/metrics/packetbeat-resources.json 2>/dev/null || true

echo ""
echo "4. Collecting cluster information..."
mkdir -p data/cluster

kubectl get nodes -o wide > data/cluster/nodes.txt
kubectl get pods --all-namespaces -o wide > data/cluster/all-pods.txt
kubectl get svc --all-namespaces > data/cluster/all-services.txt

# Cilium status
cilium status > data/cluster/cilium-status.txt 2>&1 || true

echo ""
echo "5. Creating summary..."
cat > data/SUMMARY.txt <<EOF
POC Data Export Summary
=======================
Export Date: $(date)
Cluster: cilium-poc

Data Collected:
---------------

Hubble Data:
$(find data/hubble -type f -exec ls -lh {} \; 2>/dev/null | awk '{print "  " $9 ": " $5}')

Packetbeat Data:
$(find data/packetbeat -type f -name "*.json" -o -name "*.txt" | head -10 | xargs -I {} sh -c 'ls -lh "{}" | awk "{print \"  \" \$9 \": \" \$5}"')

Total Hubble flows: $(cat data/hubble/hubble-flows-all.json 2>/dev/null | wc -l || echo "0")
Total Packetbeat events: $(cat data/packetbeat/packetbeat-combined.json 2>/dev/null | jq 'length' || echo "0")

Total data size: $(du -sh data | cut -f1)

Next Steps:
-----------
1. Run analysis: ./analysis/generate-report.sh
2. View individual data files in data/ directory
3. Import into your preferred analysis tools

EOF

cat data/SUMMARY.txt

echo ""
echo "=== Data Export Complete ==="
echo ""
echo "All data saved to: $(pwd)/data/"
echo ""
echo "Quick analysis: ./analysis/generate-report.sh"
