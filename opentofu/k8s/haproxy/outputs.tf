output "lb_names" {
  value = module.haproxy.vm_names
}

output "lb_ips" {
  value = module.haproxy.vm_ips
}
