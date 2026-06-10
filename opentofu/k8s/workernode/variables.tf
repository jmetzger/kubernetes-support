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

# --- Worker spezifisch ---
# Worker = Workernode

# Workernode Name
variable "worker_prefix" {
  type    = string
  default = "worker"
}

# Anzahl Workernodes
variable "worker_count" {
  type    = number
  default = 3
}

# IPAdresse Workernode
variable "worker_base_ip" {
  type    = string
  default = "10.78.80.230"
}

# Anzahl CPU Kerne
variable "worker_cpu" {
  type    = number
  default = 2
}

# Anzahl Arbeitsspeicher
variable "worker_ram" {
  type    = number
  default = 4
}

# Festplattengroese
variable "worker_disk" {
  type    = number
  default = 40
}

# --- vm_prefix für State-Namen ---
variable "vm_prefix" {
  type    = string
  default = "k8s"
}