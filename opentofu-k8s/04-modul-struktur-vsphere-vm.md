# Modul-Struktur: vsphere-vm

## Problem

Provider-Block und data sources waren in jedem Unterverzeichnis identisch wiederholt:

```
k8s/control-plane/main.tf  → provider + 6x data + resource
k8s/haproxy/main.tf        → provider + 6x data + resource  (Duplikat)
k8s/workernode/main.tf     → provider + 6x data + resource  (Duplikat)
```

Ausserdem: drei separate States bedeuten drei `tofu apply` Aufrufe fuer ein
vollstaendiges Cluster-Deployment.

## Loesung: Ein State, ein Provider, ein Apply

```
opentofu/
  main.tf           <- provider EINMAL
  control-plane.tf  <- module "control_plane"
  haproxy.tf        <- module "haproxy"
  workernode.tf     <- module "workernode"
  variables.tf      <- alle Variablen konsolidiert
  modules/
    vsphere-vm/
      main.tf       <- data sources + VM resource (kein Provider)
      variables.tf  <- alle Parameter
      outputs.tf    <- vm_names, vm_ips
```

Ein einziges `tofu apply` in `opentofu/` deployed HAProxy, Control Plane
und Workernodes in einem Durchgang.

## main.tf — Provider einmal

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
```

## control-plane.tf

```hcl
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
```

## haproxy.tf

```hcl
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
```

## workernode.tf

```hcl
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
```

## modules/vsphere-vm/main.tf

```hcl
# Kein provider-Block hier — kommt vom Aufrufer (main.tf)

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
variable "datacenter"      { type = string }
variable "cluster"         { type = string }
variable "datastore"       { type = string }
variable "network"         { type = string }
variable "content_library" { type = string }
variable "template_name"   { type = string }
variable "domain"          { type = string }
variable "gateway"         { type = string }
variable "dns_server"      { type = string }
variable "base_ip"         { type = string }
variable "vm_prefix"       { type = string }
variable "vm_count"        { type = number }
variable "cpu"             { type = number }
variable "ram"             { type = number }
variable "disk"            { type = number }
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

## variables.tf — alle Variablen konsolidiert

```hcl
# vSphere Verbindung
variable "vcenter_server"   { type = string; default = "vcenter.example.com" }
variable "vcenter_user"     { type = string; default = "opentofu@vsphere.local" }
variable "vcenter_password" { type = string; sensitive = true }

# vSphere Infrastruktur
variable "datacenter"      { type = string; default = "dc-01" }
variable "cluster"         { type = string; default = "dc-01" }
variable "datastore"       { type = string; default = "datastore-01" }
variable "network"         { type = string; default = "VM Network" }
variable "content_library" { type = string; default = "Packer-Templates" }
variable "template_name"   { type = string; default = "VMk8s" }

# Netzwerk
variable "domain"      { type = string; default = "k8s.example.com" }
variable "gateway"     { type = string; default = "10.0.0.1" }
variable "dns_server"  { type = string; default = "10.0.0.1" }

# Control Plane
variable "cp_prefix"   { type = string; default = "cp" }
variable "cp_count"    { type = number; default = 3 }
variable "cp_base_ip"  { type = string; default = "10.0.0.10" }
variable "cp_cpu"      { type = number; default = 4 }
variable "cp_ram"      { type = number; default = 8 }
variable "cp_disk"     { type = number; default = 40 }

# HAProxy
variable "haproxy_prefix"   { type = string; default = "k8s" }
variable "haproxy_count"    { type = number; default = 2 }
variable "haproxy_base_ip"  { type = string; default = "10.0.0.20" }

# Workernode
variable "worker_prefix"   { type = string; default = "worker" }
variable "worker_count"    { type = number; default = 3 }
variable "worker_base_ip"  { type = string; default = "10.0.0.30" }
variable "worker_cpu"      { type = number; default = 2 }
variable "worker_ram"      { type = number; default = 4 }
variable "worker_disk"     { type = number; default = 40 }
```

## Deployment

```bash
cd opentofu/
tofu init
tofu plan
tofu apply
```
