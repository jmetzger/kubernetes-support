# --- vSphere Verbindung ---
variable "vcenter_server" {
  type    = string
  default = "vcenter.example.com"
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
  default = "dc-01"
}

variable "cluster" {
  type    = string
  default = "cluster-01"
}

variable "datastore" {
  type    = string
  default = "datastore-01"
}

variable "network" {
  type    = string
  default = "VM Network"
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
  default = "k8s.example.com"
}

variable "gateway" {
  type    = string
  default = "10.0.0.1"
}

variable "dns_server" {
  type    = string
  default = "10.0.0.1"
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
  default = "10.0.0.10"
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
  default = "lb"
}

variable "haproxy_count" {
  type    = number
  default = 2
}

variable "haproxy_base_ip" {
  type    = string
  default = "10.0.0.20"
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
  default = "10.0.0.30"
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
