module "haproxy" {
  source = "./modules/vsphere-vm"

  datacenter      = var.datacenter
  cluster         = var.cluster
  datastore       = var.datastore
  network         = var.network
  content_library = var.content_library
  template_name   = var.template_name
  domain          = var.domain
  gateway         = var.gateway
  dns_server      = var.dns_server

  vm_prefix = "${var.haproxy_prefix}-lb"
  vm_count  = var.haproxy_count
  base_ip   = var.haproxy_base_ip
  cpu       = 1
  ram       = 2
  disk      = 80
}

output "lb_names" {
  value = module.haproxy.vm_names
}

output "lb_ips" {
  value = module.haproxy.vm_ips
}
