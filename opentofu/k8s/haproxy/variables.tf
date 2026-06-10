#   zugriff auf vcenter server
variable "vcenter_server" {
  type    = string
  default = "svr-poc-vcenter.mgmt.internal"
}

# vcenter Benutzer
variable "vcenter_user" {
  type    = string
  default = "opentofu@vsphere.local"
}

# Passwort vcenter user
variable "vcenter_password" {
  type      = string
  sensitive = true
}


# vcenter datacenter name
variable "datacenter" {
  type    = string
  default = "I3s"
}

# vcenter cluster Name
variable "cluster" {
  type    = string
  default = "I3s"
}

# vcenter Logical unit Number name
variable "datastore" {
  type    = string
  default = "lun-rz1-v3010"
}

# Workernode Netzwerk
variable "network" {
  type    = string
  default = "POCK8ST-V1080-80"
}

# Template Speicherort
variable "content_library" {
  type    = string
  default = "Packer-Templates"
}

# Template Name
variable "template_name" {
  type    = string
  default = "ubuntu-2404-base"
}

# DNS domain Name
variable "domain" {
  type    = string
  default = "kube.isgus.de"
}

# Netzwerk Router
variable "gateway" {
  type    = string
  default = "10.78.80.199"
}

# DNS Server IP-Adresse
variable "dns_server" {
  type    = string
  default = "10.78.75.1"
}

# Name HA-Proxy
variable "vm_prefix" {
  type = string
}

# IP_adresse HA-Proxy
variable "node_base_ip" {
  type = string
}

#Anzahl COntrol plane 
variable "cp_count" {
  type    = number
  default = 3
}

# Anzahl Workernode
variable "worker_count" {
  type    = number
  default = 3
}