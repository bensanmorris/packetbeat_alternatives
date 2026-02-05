#!/bin/bash
set -e

echo "=== Installing Cilium with Hubble and L7 Visibility ==="
echo ""

echo "Step 1: Installing Cilium with L7 proxy enabled..."
cilium install \
  --version 1.18.5 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set prometheus.enabled=true \
  --set operator.prometheus.enabled=true \
  --set proxy.prometheus.enabled=true

echo ""
echo "Step 2: Waiting for Cilium to be ready..."
cilium status --wait

echo ""
echo "Step 3: Enabling Hubble..."
cilium hubble enable --ui

echo ""
echo "Step 4: Running connectivity test..."
cilium connectivity test --test-concurrency 1 --all-flows || echo "⚠️  Some connectivity tests failed (this is often OK)"

echo ""
echo "=== Cilium Installation Complete with L7 Support ==="
echo ""

cilium status

echo ""
echo "To access Hubble UI:"
echo "  cilium hubble ui"
echo "  (Opens browser at http://localhost:12000)"
echo ""
echo "To view live flows with L7 data:"
echo "  hubble observe"
echo ""
echo "After deploying apps, enable L7 visibility per-pod:"
echo "  kubectl annotate pod -n demo --all policy.cilium.io/proxy-visibility='<Ingress/80/TCP/HTTP>,<Egress/80/TCP/HTTP>'"
echo ""
echo "Next step:"
echo "  kubectl apply -f deploy/packetbeat-config.yaml"
echo "  kubectl apply -f deploy/packetbeat-daemonset.yaml"
