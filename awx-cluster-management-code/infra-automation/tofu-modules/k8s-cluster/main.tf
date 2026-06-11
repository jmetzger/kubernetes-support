# Kubernetes Cluster Modul
# Provider-spezifische Implementierung hier einfügen (OpenStack, vSphere, Hetzner, ...)
#
# Dieses Modul erwartet folgende Ressourcen vom Provider:
#   - Netzwerke / Subnetze für haproxy, cp, worker
#   - VMs für HAProxy (typisch 2x), Control Plane, Worker
#   - Floating IP / VIP für den API-Server

terraform {
  required_providers {
    # Beispiel OpenStack:
    # openstack = {
    #   source  = "terraform-provider-openstack/openstack"
    #   version = "~> 1.54"
    # }
  }
}

# --- Netzwerk ---

# resource "openstack_networking_network_v2" "haproxy" {
#   name = "${var.cluster_name}-haproxy"
# }
#
# resource "openstack_networking_subnet_v2" "haproxy" {
#   name       = "${var.cluster_name}-haproxy"
#   network_id = openstack_networking_network_v2.haproxy.id
#   cidr       = var.haproxy_subnet
# }
#
# resource "openstack_networking_subnet_v2" "cp" {
#   name = "${var.cluster_name}-cp"
#   cidr = var.cp_subnet
# }
#
# resource "openstack_networking_subnet_v2" "worker" {
#   name = "${var.cluster_name}-worker"
#   cidr = var.worker_subnet
# }

# --- HAProxy Nodes ---

# resource "openstack_compute_instance_v2" "haproxy" {
#   count  = 2
#   name   = "${var.cluster_name}-haproxy-${count.index + 1}"
#   flavor_name = var.worker_flavor
#   ...
# }

# --- Control Plane Nodes ---

# resource "openstack_compute_instance_v2" "control_plane" {
#   count  = var.control_plane_count
#   name   = "${var.cluster_name}-cp-${count.index + 1}"
#   ...
# }

# --- Worker Nodes ---

# resource "openstack_compute_instance_v2" "worker" {
#   count  = var.worker_count
#   name   = "${var.cluster_name}-worker-${count.index + 1}"
#   flavor_name = var.worker_flavor
#   ...
# }
