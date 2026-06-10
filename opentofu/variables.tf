# --- vSphere Verbindung ---
variable "vcenter_server" {
  type    = string
  default = "svr-poc-vcenter.mgmt.internal"
}

variable "vcenter_user" {
  type    = string
  default = "opentofu@vsphere.local"
}

variable "vcenter_password" {
  type      = string
  sensitive = true
}

# --- vSphere Infrastruktur ---
variable "datacenter" {
  type    = string
  default = "I3s"
}

variable "cluster" {
  type    = string
  default = "I3s"
}

variable "datastore" {
  type    = string
  default = "lun-rz1-v3010"
}

variable "network" {
  type    = string
  default = "POCK8ST-V1080-80"
}

variable "content_library" {
  type    = string
  default = "Packer-Templates"
}

variable "template_name" {
  type    = string
  default = "VMk8s"
}

# --- Netzwerk ---
variable "domain" {
  type    = string
  default = "kube.isgus.de"
}

variable "gateway" {
  type    = string
  default = "10.78.80.199"
}

variable "dns_server" {
  type    = string
  default = "10.78.75.1"
}

# --- Control Plane ---
variable "cp_prefix" {
  type    = string
  default = "cp"
}

variable "cp_count" {
  type    = number
  default = 3
}

variable "cp_base_ip" {
  type    = string
  default = "10.78.80.220"
}

variable "cp_cpu" {
  type    = number
  default = 4
}

variable "cp_ram" {
  type    = number
  default = 8
}

variable "cp_disk" {
  type    = number
  default = 40
}

# --- HAProxy ---
variable "haproxy_prefix" {
  type    = string
  default = "k8s"
}

variable "haproxy_count" {
  type    = number
  default = 2
}

variable "haproxy_base_ip" {
  type    = string
  default = "10.78.80.210"
}

# --- Workernode ---
variable "worker_prefix" {
  type    = string
  default = "worker"
}

variable "worker_count" {
  type    = number
  default = 3
}

variable "worker_base_ip" {
  type    = string
  default = "10.78.80.230"
}

variable "worker_cpu" {
  type    = number
  default = 2
}

variable "worker_ram" {
  type    = number
  default = 4
}

variable "worker_disk" {
  type    = number
  default = 40
}
