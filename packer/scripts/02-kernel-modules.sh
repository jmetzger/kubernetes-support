#!/bin/bash
set -euo pipefail

echo ">>> Kernel-Module für Kubernetes"
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
