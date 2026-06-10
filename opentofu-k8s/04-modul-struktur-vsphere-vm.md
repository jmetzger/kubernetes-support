# Modul-Struktur: vsphere-vm

## Problem

Provider-Block und data sources sind in jedem Unterverzeichnis identisch wiederholt:

```
k8s/Control-Plane/main.tf  → provider + 6x data + resource
k8s/HAProxy/main.tf        → provider + 6x data + resource  (Duplikat)
k8s/Workernode/main.tf     → provider + 6x data + resource  (Duplikat)
```

Aenderung an einer Stelle (z.B. vSphere-Version) muss 3x gemacht werden.

## Loesung: Modul

```
opentofu/
  modules/
    vsphere-vm/
      main.tf       <- data sources + VM resource (kein Provider)
      variables.tf  <- alle Parameter
      outputs.tf    <- vm_names, vm_ips
  k8s/
    Control-Plane/
      main.tf       <- provider + module-Aufruf
    HAProxy/
      main.tf       <- provider + module-Aufruf
    Workernode/
      main.tf       <- provider + module-Aufruf
```

## modules/vsphere-vm/main.tf

```hcl
# Kein provider-Block hier — der kommt vom Aufrufer

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
```

## modules/vsphere-vm/variables.tf

```hcl
# vSphere Verbindung
variable "datacenter"      { type = string }
variable "cluster"         { type = string }
variable "datastore"       { type = string }
variable "network"         { type = string }
variable "content_library" { type = string }
variable "template_name"   { type = string }

# Netzwerk
variable "domain"     { type = string }
variable "gateway"    { type = string }
variable "dns_server" { type = string }
variable "base_ip"    { type = string }

# VM
variable "vm_prefix" { type = string }
variable "vm_count"  { type = number }
variable "cpu"       { type = number }
variable "ram"       { type = number }  # in GB
variable "disk"      { type = number }  # in GB
```

## modules/vsphere-vm/outputs.tf

```hcl
output "vm_names" {
  value = vsphere_virtual_machine.vm[*].name
}

output "vm_ips" {
  value = vsphere_virtual_machine.vm[*].default_ip_address
}
```

## k8s/Control-Plane/main.tf (Aufrufer)

```hcl
terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.6"
    }
  }
}

provider "vsphere" {
  user                 = var.vcenter_user
  password             = var.vcenter_password
  vsphere_server       = var.vcenter_server
  allow_unverified_ssl = true
}

module "control_plane" {
  source = "../../modules/vsphere-vm"

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
```

## k8s/HAProxy/main.tf (Aufrufer)

```hcl
terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.6"
    }
  }
}

provider "vsphere" {
  user                 = var.vcenter_user
  password             = var.vcenter_password
  vsphere_server       = var.vcenter_server
  allow_unverified_ssl = true
}

module "haproxy" {
  source = "../../modules/vsphere-vm"

  datacenter      = var.datacenter
  cluster         = var.cluster
  datastore       = var.datastore
  network         = var.network
  content_library = var.content_library
  template_name   = var.template_name
  domain          = var.domain
  gateway         = var.gateway
  dns_server      = var.dns_server

  vm_prefix = "${var.vm_prefix}-lb"
  vm_count  = 2
  base_ip   = var.node_base_ip
  cpu       = 1
  ram       = 2
  disk      = 80
}
```

## k8s/Workernode/main.tf (Aufrufer)

```hcl
terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.6"
    }
  }
}

provider "vsphere" {
  user                 = var.vcenter_user
  password             = var.vcenter_password
  vsphere_server       = var.vcenter_server
  allow_unverified_ssl = true
}

module "workernode" {
  source = "../../modules/vsphere-vm"

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
```

## Warum der Provider in jedem Verzeichnis bleibt

Jedes Unterverzeichnis ist ein eigener OpenTofu State — Control-Plane, HAProxy und
Workernode werden unabhaengig voneinander deployed. Deshalb braucht jedes seinen
eigenen Provider-Block.

Was im Modul steckt und nicht mehr dupliziert ist: die 6 data sources und die
VM-Resource.
