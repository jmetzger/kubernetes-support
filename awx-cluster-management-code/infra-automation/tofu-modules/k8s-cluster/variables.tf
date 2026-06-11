variable "cluster_name" {
  type        = string
  description = "Name des Kubernetes-Clusters"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes Version (z.B. 1.30)"
}

variable "k8s_distro" {
  type        = string
  description = "Kubernetes Distribution (rke2, k3s, kubeadm)"
  default     = "rke2"
}

variable "worker_count" {
  type        = number
  description = "Anzahl Worker Nodes"
}

variable "worker_flavor" {
  type        = string
  description = "VM-Flavor für Worker Nodes (z.B. c3.large)"
}

variable "control_plane_count" {
  type        = number
  description = "Anzahl Control Plane Nodes (1 oder 3)"
  default     = 3
}

variable "calico_version" {
  type        = string
  description = "Calico CNI Version"
}

variable "containerd_version" {
  type        = string
  description = "containerd Version"
}

variable "haproxy_subnet" {
  type        = string
  description = "Subnetz für HAProxy Nodes (CIDR /24)"
}

variable "cp_subnet" {
  type        = string
  description = "Subnetz für Control Plane Nodes (CIDR /24)"
}

variable "worker_subnet" {
  type        = string
  description = "Subnetz für Worker Nodes (CIDR /24)"
}
