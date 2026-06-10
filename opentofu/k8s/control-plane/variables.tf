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

# Control-plane Netzwerk
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
  default = "VMk8s"
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

# --- Control Plane spezifisch ---
# cp = Control-Plane 
#Control-Plane Name
variable "cp_prefix" {
  type    = string
  default = "cp"
}

# Control Plane Anzahl
variable "cp_count" {
  type    = number
  default = 3
}

# cp IP_adresse
variable "cp_base_ip" {
  type    = string
  default = "10.78.80.220"
}

#cp CPU Kerne
variable "cp_cpu" {
  type    = number
  default = 4
}

# cp Arbeitsspeicher
variable "cp_ram" {
  type    = number
  default = 8
}

# cp Disk Größe
variable "cp_disk" {
  type    = number
  default = 40
}

# --- vm_prefix für State-Namen ---
variable "vm_prefix" {
  type    = string
  default = "k8s"
}