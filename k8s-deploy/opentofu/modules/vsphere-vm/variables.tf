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
