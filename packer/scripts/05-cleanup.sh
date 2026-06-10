#!/bin/bash
set -euo pipefail

echo ">>> Cleanup für Template"
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# Cloud-init zurücksetzen für Template
cloud-init clean --logs

# Machine-ID leeren (wird beim Klonen neu generiert)
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# SSH Host-Keys entfernen (werden beim Boot neu erzeugt)
rm -f /etc/ssh/ssh_host_*

# alte netconfig rausnehmen, damit proxmox übernehmen kann
rm -f /etc/netplan/00-installer-config.yaml
rm -f /etc/netplan/50-cloud-init.yaml

echo ">>> Template bereit"
