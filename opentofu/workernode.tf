module "workernode" {
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

  vm_prefix = var.worker_prefix
  vm_count  = var.worker_count
  base_ip   = var.worker_base_ip
  cpu       = var.worker_cpu
  ram       = var.worker_ram
  disk      = var.worker_disk
}

output "worker_names" {
  value = module.workernode.vm_names
}

output "worker_ips" {
  value = module.workernode.vm_ips
}
