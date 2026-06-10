output "vm_names" {
  value = vsphere_virtual_machine.vm[*].name
}

output "vm_ips" {
  value = vsphere_virtual_machine.vm[*].default_ip_address
}
