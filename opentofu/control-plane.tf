module "control_plane" {
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

  vm_prefix = var.cp_prefix
  vm_count  = var.cp_count
  base_ip   = var.cp_base_ip
  cpu       = var.cp_cpu
  ram       = var.cp_ram
  disk      = var.cp_disk
}

output "cp_names" {
  value = module.control_plane.vm_names
}

output "cp_ips" {
  value = module.control_plane.vm_ips
}
