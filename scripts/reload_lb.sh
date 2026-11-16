#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

NODE_A1_IP=$(sudo docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' multisite-ha-cluster-worker)
NODE_A2_IP=$(sudo docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' multisite-ha-cluster-worker2)
NODE_B1_IP=$(sudo docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' multisite-ha-cluster-worker3)
NODE_B2_IP=$(sudo docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' multisite-ha-cluster-worker4)

sed -e "s/__SITE_A_NODE1_IP__/${NODE_A1_IP}/g" \
    -e "s/__SITE_A_NODE2_IP__/${NODE_A2_IP}/g" \
    -e "s/__SITE_B_NODE1_IP__/${NODE_B1_IP}/g" \
    -e "s/__SITE_B_NODE2_IP__/${NODE_B2_IP}/g" \
    "${PROJECT_ROOT}/lb/haproxy.cfg.template" > "${PROJECT_ROOT}/lb/haproxy.cfg"

sudo docker restart edge-loadbalancer
echo "Edge Load Balancer reloaded with updated configuration."
