#!/bin/bash
set -euo pipefail

# Host to IP mapping
declare -A HOST_MAP=(
  ["k8s-tunnel-v1"]="10.10.10.10/24"
  ["k8s-node-v1"]="10.10.10.11/24"
  ["k8s-node-v2"]="10.10.10.12/24"
  ["k8s-node-v3"]="10.10.10.13/24"
  ["k8s-node-p1"]="10.10.10.14/24"
  ["k8s-node-p2"]="10.10.10.15/24"
  ["k8s-node-p3"]="10.10.10.14/24"
  ["k8s-node-p4"]="10.10.10.15/24"
)

# Gateway
GATEWAY="10.10.10.1"

# Hosts file entries
HOSTS_BLOCK=$(cat <<EOF
10.10.10.10 "k8s-tunnel-v1
10.10.10.11 k8s-node-v1
10.10.10.12 k8s-node-v2
10.10.10.13 k8s-node-v3
10.10.10.14 k8s-node-p1
10.10.10.15 k8s-node-p2
10.10.10.14 k8s-node-p3
10.10.10.15 k8s-node-p4
EOF
)

# Detect hostname
HOSTNAME_CURRENT=$(hostname)
echo "Detected hostname: $HOSTNAME_CURRENT"

# Step 1: Update /etc/hosts
echo "Updating /etc/hosts..."
cp /etc/hosts /etc/hosts.bak.$(date +%F-%T)
sed -i '/k8s-tunnel-v1/d;/k8s-node-v1/d;/k8s-node-v2/d;/k8s-node-v3/d;/k8s-node-v4/d;/k8s-node-v5/d;/k8s-node-v6/d;/k8s-node-p1/d;/k8s-node-p2/d;/k8s-node-p3/d;/k8s-node-p4/d' /etc/hosts
echo "$HOSTS_BLOCK" >> /etc/hosts

# Step 2: Update hostname + static IP if in map
if [[ -v HOST_MAP[$HOSTNAME_CURRENT] ]]; then
    NEW_IP=${HOST_MAP[$HOSTNAME_CURRENT]}
    echo "Setting static IP for $HOSTNAME_CURRENT → $NEW_IP"

    # Find the primary interface
    IFACE=$(nmcli device status | awk '$2=="ethernet" && $3=="connected" {print $1; exit}')
    echo "Using interface: $IFACE"

    # Set hostname
    echo "Updating hostname..."
    hostnamectl set-hostname "$HOSTNAME_CURRENT"

    # Configure static IP via nmcli
    nmcli con mod "$IFACE" ipv4.addresses "$NEW_IP"
    nmcli con mod "$IFACE" ipv4.gateway "$GATEWAY"
    nmcli con mod "$IFACE" ipv4.dns "10.10.10.1 1.1.1.1"
    nmcli con mod "$IFACE" ipv4.method manual
    nmcli con up "$IFACE"

    echo "✅ Hostname + Static IP applied successfully"
    echo "   Hostname   : $HOSTNAME_CURRENT"
    echo "   IP Address : $NEW_IP"
    echo "   Gateway    : $GATEWAY"
    echo "   Interface  : $IFACE"
else
    echo "⚠️ Hostname $HOSTNAME_CURRENT not in HOST_MAP. No IP changes made."
fi
