#!/bin/bash
set -euo pipefail

echo ">>> System-Updates"
apt-get update
apt-get upgrade -y

# Swap wird erst garnicht angelegt (user-data),
# Deshalb brauchen wir es nicht deaktivieren
# echo ">>> Swap deaktivieren"
# swapoff -a
# sed -i '/ swap / s/^/#/' /etc/fstab

echo ">>> IPv4 Forwarding & Bridge-Netfilter"
cat > /etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
