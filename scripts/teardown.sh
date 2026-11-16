#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/teardown.sh
# Purpose: Cleanly destroys all cluster, network, and load balancer resources
# ==============================================================================
set -uo pipefail

echo "=================================================================="
echo " [Teardown] Cleaning up Multi-Site Resilient HA Platform"
echo "=================================================================="

# 1. Stop and remove Edge Load Balancer
echo "==> Removing Edge Load Balancer container..."
sudo docker rm -f edge-loadbalancer 2>/dev/null || true

# 2. Delete KinD Kubernetes Cluster
echo "==> Deleting Kubernetes Cluster (multisite-ha-cluster)..."
if command -v kind >/dev/null 2>&1; then
    kind delete cluster --name multisite-ha-cluster 2>/dev/null || true
fi

# 3. Remove Multi-Site Docker Networks
echo "==> Removing Multi-Site Docker Networks..."
for net in site-a-lan site-b-lan wan-backbone; do
    sudo docker network rm "$net" 2>/dev/null || true
done

# 4. Clean up iptables forwarding rules
echo "==> Flushing custom iptables forward rules..."
sudo iptables -D FORWARD -i br-site-a -o br-site-b -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i br-site-b -o br-site-a -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i br-wan -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -o br-wan -j ACCEPT 2>/dev/null || true

echo "=================================================================="
echo " ==> Clean Teardown Complete! Environment is back to baseline.   "
echo "=================================================================="
