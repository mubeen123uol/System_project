#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/deploy.sh
# Purpose: End-to-end automated deployment of Multi-Site Resilient HA Platform
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=================================================================="
echo " [PHASE 1/5] Verifying Dependencies and Prerequisites"
echo "=================================================================="
"${PROJECT_ROOT}/scripts/install_tools.sh"

echo "=================================================================="
echo " [PHASE 2/5] Cleaning Existing State & Provisioning Multi-Site Networks"
echo "=================================================================="
# Clean up any previously existing cluster or networks
"${PROJECT_ROOT}/scripts/teardown.sh" || true
"${PROJECT_ROOT}/network/setup_multisite_net.sh"

echo "=================================================================="
echo " [PHASE 3/5] Deploying Multi-Site Kubernetes Cluster via KinD"
echo "=================================================================="
CLUSTER_NAME="multisite-ha-cluster"

echo "==> Creating 5-node HA multi-zone cluster from code..."
kind create cluster --config "${PROJECT_ROOT}/config/multi-site-cluster.yaml" --image kindest/node:v1.32.2 --wait 180s

echo "==> Waiting for all nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Attach Worker Nodes to Simulated Multi-Site LANs
echo "==> Connecting worker nodes to isolated multi-site networks..."
sudo docker network connect site-a-lan multisite-ha-cluster-worker 2>/dev/null || true
sudo docker network connect site-a-lan multisite-ha-cluster-worker2 2>/dev/null || true
sudo docker network connect site-b-lan multisite-ha-cluster-worker3 2>/dev/null || true
sudo docker network connect site-b-lan multisite-ha-cluster-worker4 2>/dev/null || true

# Explicitly ensure node labels are assigned
echo "==> Applying site topology labels..."
kubectl label node multisite-ha-cluster-worker topology.kubernetes.io/zone=site-a datacenter=site-a --overwrite
kubectl label node multisite-ha-cluster-worker2 topology.kubernetes.io/zone=site-a datacenter=site-a --overwrite
kubectl label node multisite-ha-cluster-worker3 topology.kubernetes.io/zone=site-b datacenter=site-b --overwrite
kubectl label node multisite-ha-cluster-worker4 topology.kubernetes.io/zone=site-b datacenter=site-b --overwrite

echo "==> Cluster node distribution:"
kubectl get nodes -L topology.kubernetes.io/zone,datacenter

echo "=================================================================="
echo " [PHASE 4/5] Deploying Resilient HA Application Workload"
echo "=================================================================="
kubectl apply -f "${PROJECT_ROOT}/manifests/01-namespace.yaml"
kubectl apply -f "${PROJECT_ROOT}/manifests/02-app-config.yaml"
kubectl apply -f "${PROJECT_ROOT}/manifests/03-ha-deployment.yaml"
kubectl apply -f "${PROJECT_ROOT}/manifests/04-service.yaml"
kubectl apply -f "${PROJECT_ROOT}/manifests/05-poddisruptionbudget.yaml"

echo "==> Waiting for HA application rollout across sites..."
kubectl rollout status deployment/ha-web-service -n ha-platform --timeout=180s

echo "==> Verified Pod Placement Across Sites:"
kubectl get pods -n ha-platform -o wide

echo "=================================================================="
echo " [PHASE 5/5] Deploying Global Edge Load Balancer (HAProxy)"
echo "=================================================================="
# Retrieve node IP addresses from the docker network
NODE_A1_IP=$(sudo docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' multisite-ha-cluster-worker)
NODE_A2_IP=$(sudo docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' multisite-ha-cluster-worker2)
NODE_B1_IP=$(sudo docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' multisite-ha-cluster-worker3)
NODE_B2_IP=$(sudo docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' multisite-ha-cluster-worker4)

echo "==> Discovered Node IP Endpoints:"
echo "    Site-A Worker 1: ${NODE_A1_IP}"
echo "    Site-A Worker 2: ${NODE_A2_IP}"
echo "    Site-B Worker 1: ${NODE_B1_IP}"
echo "    Site-B Worker 2: ${NODE_B2_IP}"

# Render active HAProxy config
sed -e "s/__SITE_A_NODE1_IP__/${NODE_A1_IP}/g" \
    -e "s/__SITE_A_NODE2_IP__/${NODE_A2_IP}/g" \
    -e "s/__SITE_B_NODE1_IP__/${NODE_B1_IP}/g" \
    -e "s/__SITE_B_NODE2_IP__/${NODE_B2_IP}/g" \
    "${PROJECT_ROOT}/lb/haproxy.cfg.template" > "${PROJECT_ROOT}/lb/haproxy.cfg"

# Stop existing LB container if running
sudo docker rm -f edge-loadbalancer 2>/dev/null || true

# Start HAProxy Edge Load Balancer
echo "==> Starting Edge Load Balancer container..."
sudo docker run -d \
    --name edge-loadbalancer \
    --restart unless-stopped \
    --network kind \
    -p 80:80 \
    -p 8404:8404 \
    -v "${PROJECT_ROOT}/lb/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
    haproxy:2.8-alpine

# Connect LB to simulated site networks as well
sudo docker network connect site-a-lan edge-loadbalancer 2>/dev/null || true
sudo docker network connect site-b-lan edge-loadbalancer 2>/dev/null || true

# Wait for HAProxy to initialize health checks
sleep 4

HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

echo "=================================================================="
echo " ==> PLATFORM DEPLOYMENT COMPLETE & OPERATIONAL! <==              "
echo "=================================================================="
echo " - Unified Edge Gateway:  http://${HOST_IP}/ (or http://127.0.0.1/)"
echo " - HA Stats Dashboard:    http://${HOST_IP}:8404/stats"
echo " - Health Endpoint:       http://${HOST_IP}/healthz"
echo "=================================================================="
