#!/bin/bash
set -e

echo "=== Cleaning Up POC Data ==="
echo ""
echo "This will remove collected data but keep the cluster running."
echo ""

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo "Removing data directories..."
rm -rf data/
rm -rf reports/

echo "Stopping traffic generators..."
kubectl delete pod -n demo -l app=traffic-gen --ignore-not-found=true

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Cluster is still running. You can:"
echo "  • Generate new traffic: ./testing/generate-traffic.sh"
echo "  • Collect new data: ./collection/export-all.sh"
echo ""
echo "To remove the cluster: ./cleanup/cleanup-all.sh"
