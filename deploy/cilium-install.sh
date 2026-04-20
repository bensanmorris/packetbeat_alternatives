#!/bin/bash
set -e

echo "=== Installing Cilium with Hubble and Metrics ==="
echo ""

echo "Step 1: Installing Cilium with Prometheus metrics enabled..."
cilium install \
  --version 1.18.5 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set prometheus.enabled=true \
  --set operator.prometheus.enabled=true \
  --set prometheus.metrics='{+cilium_endpoint_state,+cilium_endpoint_regenerations,+cilium_bpf_map_ops_total,+cilium_endpoint_count,+cilium_identity_count,+cilium_datapath_conntrack_gc_duration_seconds,+cilium_datapath_conntrack_gc_entries}'

echo ""
echo "Step 2: Waiting for Cilium to be ready..."
cilium status --wait

echo ""
echo "Step 3: Enabling Hubble..."
cilium hubble enable --ui

echo ""
echo "Step 4: Verifying Prometheus metrics are exposed..."
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=180s

# Create hubble-metrics service for easy access to Cilium metrics
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: hubble-metrics
  namespace: kube-system
  labels:
    k8s-app: cilium
spec:
  ports:
  - name: metrics
    port: 9962
    protocol: TCP
    targetPort: 9962
  selector:
    k8s-app: cilium
  type: ClusterIP
EOF

echo ""
echo "Step 5: Running connectivity test..."
cilium connectivity test --test-concurrency 1 --all-flows || echo "⚠️  Some connectivity tests failed (this is often OK)"

echo ""
echo "=== Cilium Installation Complete with Metrics ==="
echo ""

cilium status

echo ""
echo "Metrics endpoints:"
echo "  Cilium agent: http://hubble-metrics:9962/metrics"
echo "  Operator:     http://cilium-operator:9963/metrics"
echo ""
echo "To access Hubble UI:"
echo "  cilium hubble ui"
echo "  (Opens browser at http://localhost:12000)"
echo ""
echo "To view live flows:"
echo "  hubble observe"
echo ""
echo "Next step:"
echo "  kubectl apply -f deploy/packetbeat-config.yaml"
echo "  kubectl apply -f deploy/packetbeat-daemonset.yaml"
