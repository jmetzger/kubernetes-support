output "cluster_name" {
  value = var.cluster_name
}

output "api_endpoint" {
  description = "Kubernetes API Server Endpoint"
  value       = "https://${var.cluster_name}-api.example.com:6443"
}

# output "haproxy_ips" {
#   value = openstack_compute_instance_v2.haproxy[*].access_ip_v4
# }
#
# output "control_plane_ips" {
#   value = openstack_compute_instance_v2.control_plane[*].access_ip_v4
# }
#
# output "worker_ips" {
#   value = openstack_compute_instance_v2.worker[*].access_ip_v4
# }
