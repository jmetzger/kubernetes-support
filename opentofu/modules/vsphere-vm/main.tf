# Kein provider-Block hier — der kommt vom Aufrufer (control-plane/, haproxy/, workernode/)

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_datastore" "ds" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "net" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_content_library" "library" {
  name = var.content_library
}

data "vsphere_content_library_item" "template" {
  name       = var.template_name
  library_id = data.vsphere_content_library.library.id
  type       = "vm-template"
}

locals {
  ip_prefix = join(".", slice(split(".", var.base_ip), 0, 3))
  ip_start  = tonumber(split(".", var.base_ip)[3])
}

resource "vsphere_virtual_machine" "vm" {
  count            = var.vm_count
  name             = "${var.vm_prefix}-${count.index + 1}"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.ds.id
  num_cpus         = var.cpu
  memory           = var.ram * 1024
  guest_id         = "ubuntu64Guest"

  network_interface {
    network_id   = data.vsphere_network.net.id
    adapter_type = "vmxnet3"
  }

  disk {
    label            = "disk0"
    size             = var.disk
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_content_library_item.template.id

    customize {
      linux_options {
        host_name = "${var.vm_prefix}-${count.index + 1}"
        domain    = var.domain
      }
      network_interface {
        ipv4_address = "${local.ip_prefix}.${local.ip_start + count.index}"
        ipv4_netmask = 24
      }
      ipv4_gateway    = var.gateway
      dns_server_list = [var.dns_server]
    }
  }
}
