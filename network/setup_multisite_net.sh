#!/usr/bin/env bash
# ==============================================================================
# Script: network/setup_multisite_net.sh
# Purpose: Simulates a multi-site WAN network topology with Site-A and Site-B
# ==============================================================================
set -euo pipefail

SITE_A_SUBNET="172.28.10.0/24"
SITE_A_GW="172.28.10.1"

SITE_B_SUBNET="172.28.20.0/24"
SITE_B_GW="172.28.20.1"

WAN_SUBNET="172.28.0.0/24"
WAN_GW="172.28.0.1"

echo "=================================================================="
echo " [Network Phase] Initializing Multi-Site Network Topology"
echo "=================================================================="

# 1. Enable Host IP Forwarding
echo "==> Enabling Linux IPv4 Packet Forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null

# 2. Cleanup existing networks if present
for net in site-a-lan site-b-lan wan-backbone; do
    if sudo docker network inspect "$net" >/dev/null 2>&1; then
        echo "==> Disconnecting any connected endpoints and removing network: $net"
        for c in $(sudo docker network inspect "$net" -f '{{range $id, $c := .Containers}}{{$id}} {{end}}' 2>/dev/null); do
            sudo docker network disconnect -f "$net" "$c" 2>/dev/null || true
        done
        sudo docker network rm "$net" >/dev/null 2>&1 || true
    fi
done

# 3. Create isolated subnets with custom bridge names
echo "==> Creating Site-A Network (Primary DC: ${SITE_A_SUBNET})..."
sudo docker network create \
    --driver bridge \
    --subnet "${SITE_A_SUBNET}" \
    --gateway "${SITE_A_GW}" \
    --opt "com.docker.network.bridge.name"="br-site-a" \
    site-a-lan

echo "==> Creating Site-B Network (Disaster Recovery DC: ${SITE_B_SUBNET})..."
sudo docker network create \
    --driver bridge \
    --subnet "${SITE_B_SUBNET}" \
    --gateway "${SITE_B_GW}" \
    --opt "com.docker.network.bridge.name"="br-site-b" \
    site-b-lan

echo "==> Creating WAN / Edge Network (${WAN_SUBNET})..."
sudo docker network create \
    --driver bridge \
    --subnet "${WAN_SUBNET}" \
    --gateway "${WAN_GW}" \
    --opt "com.docker.network.bridge.name"="br-wan" \
    wan-backbone

# 4. Configure iptables routing between Site-A and Site-B bridges
echo "==> Configuring Cross-Site Routing and WAN forwarding rules..."
sudo iptables -D FORWARD -i br-site-a -o br-site-b -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i br-site-b -o br-site-a -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i br-wan -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -o br-wan -j ACCEPT 2>/dev/null || true

sudo iptables -I FORWARD 1 -i br-site-a -o br-site-b -j ACCEPT
sudo iptables -I FORWARD 1 -i br-site-b -o br-site-a -j ACCEPT
sudo iptables -I FORWARD 1 -i br-wan -j ACCEPT
sudo iptables -I FORWARD 1 -o br-wan -j ACCEPT

# 5. Apply WAN latency simulation (15ms cross-site propagation delay)
echo "==> Applying WAN Emulation (15ms inter-site latency on br-site-b)..."
sudo tc qdisc del dev br-site-b root 2>/dev/null || true
sudo tc qdisc add dev br-site-b root netem delay 15ms 2ms distribution normal || true

echo "=================================================================="
echo " ==> Multi-Site Network Topology Ready!                           "
echo "  - Site-A LAN: ${SITE_A_SUBNET} (br-site-a)"
echo "  - Site-B LAN: ${SITE_B_SUBNET} (br-site-b, 15ms simulated WAN delay)"
echo "  - WAN Edge:   ${WAN_SUBNET} (br-wan)"
echo "=================================================================="
