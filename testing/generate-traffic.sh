#!/bin/bash
set -e

echo "=== Generating Test Traffic ==="
echo ""

# Check if demo namespace exists
if ! kubectl get namespace demo &> /dev/null; then
    echo "ERROR: demo namespace not found"
    echo "Please deploy test app first: kubectl apply -f deploy/test-app.yaml"
    exit 1
fi

# Wait for pods to be ready
echo "Waiting for demo pods to be ready..."
kubectl wait --for=condition=ready pod --all -n demo --timeout=120s

echo ""
echo "Deploying traffic generators..."
echo ""

# Deploy HTTP traffic generator
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: traffic-gen-http
  namespace: demo
  labels:
    app: traffic-gen
    type: http
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["/bin/sh"]
    args:
      - -c
      - |
        echo "Starting HTTP traffic generation..."
        while true; do
          # Frontend requests
          curl -s http://frontend/ > /dev/null || true
          
          # Backend API requests
          curl -s http://backend/get > /dev/null || true
          curl -s http://backend/post -X POST -d '{"test":"data"}' > /dev/null || true
          curl -s http://backend/status/200 > /dev/null || true
          
          # Random delay
          sleep \$((RANDOM % 5 + 1))
        done
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
      limits:
        cpu: 50m
        memory: 32Mi
EOF

# Deploy DNS traffic generator
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: traffic-gen-dns
  namespace: demo
  labels:
    app: traffic-gen
    type: dns
spec:
  containers:
  - name: dns
    image: busybox:latest
    command: ["/bin/sh"]
    args:
      - -c
      - |
        echo "Starting DNS traffic generation..."
        while true; do
          nslookup frontend.demo.svc.cluster.local || true
          nslookup backend.demo.svc.cluster.local || true
          nslookup database.demo.svc.cluster.local || true
          nslookup kubernetes.default.svc.cluster.local || true
          sleep 10
        done
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
      limits:
        cpu: 50m
        memory: 32Mi
EOF

# Deploy failed connection generator
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: traffic-gen-failed
  namespace: demo
  labels:
    app: traffic-gen
    type: failed
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["/bin/sh"]
    args:
      - -c
      - |
        echo "Starting failed connection generation..."
        while true; do
          # Try to connect to non-existent services
          curl -s http://nonexistent-service/ --max-time 2 > /dev/null 2>&1 || true
          curl -s http://blocked-service.demo/ --max-time 2 > /dev/null 2>&1 || true
          
          # Try to connect to blocked ports
          curl -s http://frontend:8080/ --max-time 2 > /dev/null 2>&1 || true
          
          sleep 15
        done
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
      limits:
        cpu: 50m
        memory: 32Mi
EOF

echo ""
echo "Waiting for traffic generators to start..."
sleep 5

echo ""
echo "=== Traffic Generation Started ==="
echo ""
echo "Running traffic generators:"
kubectl get pods -n demo -l app=traffic-gen

echo ""
echo "To view live traffic:"
echo "  Hubble: hubble observe --namespace demo"
echo "  Packetbeat: kubectl logs -n monitoring -l app=packetbeat -f"
echo ""
echo "To stop traffic generation:"
echo "  kubectl delete pod -n demo -l app=traffic-gen"
