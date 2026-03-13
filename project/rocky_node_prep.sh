#!/bin/bash
set -euo pipefail

# Host to IP mapping
declare -A HOST_MAP=(
  ["tunnel-vm"]="192.168.1.101/24"
  ["k8s-node-1"]="192.168.1.111/24"
  ["k8s-node-2"]="192.168.1.112/24"
  ["k8s-node-3"]="192.168.1.113/24"
  ["k8s-node-4"]="192.168.1.114/24"
  ["k8s-node-5"]="192.168.1.115/24"
  ["k8s-node-6"]="192.168.1.116/24"
  ["ceph-node-1"]="192.168.1.131/24"
  ["ceph-node-2"]="192.168.1.132/24"
  ["ceph-node-3"]="192.168.1.133/24"
)

# Gateway
GATEWAY="192.168.1.1"

# Hosts file entries
HOSTS_BLOCK=$(cat <<EOF
192.168.1.110 tunnel-vm
192.168.1.111 k8s-node-1
192.168.1.112 k8s-node-2
192.168.1.113 k8s-node-3
192.168.1.114 k8s-node-4
192.168.1.115 k8s-node-5
192.168.1.116 k8s-node-6
192.168.1.131 ceph-node-1
192.168.1.132 ceph-node-2
192.168.1.133 ceph-node-3
EOF
)

# Detect hostname
HOSTNAME_CURRENT=$(hostname)
echo "Detected hostname: $HOSTNAME_CURRENT"

# Step 1: Update /etc/hosts
echo "Updating /etc/hosts..."
cp /etc/hosts /etc/hosts.bak.$(date +%F-%T)
sed -i '/tunnel-vm/d;/k8s-node-1/d;/k8s-node-2/d;/k8s-node-3/d;/k8s-node-4/d;/k8s-node-5/d;/k8s-node-6/d;/ceph-node-1/d;/ceph-node-2/d;/ceph-node-3/d' /etc/hosts
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
    nmcli con mod "$IFACE" ipv4.dns "192.168.1.1 1.1.1.1"
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
