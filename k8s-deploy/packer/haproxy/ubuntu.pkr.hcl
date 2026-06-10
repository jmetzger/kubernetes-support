packer {
  required_plugins {
    vsphere = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/vsphere"
    }
  }
}

# --- Verbindung ---
variable "vcenter_server"   { type = string }
variable "vcenter_user"     { type = string; default = "opentofu@vsphere.local" }
variable "vcenter_password" { type = string; sensitive = true }

# --- vSphere Infrastruktur ---
variable "datacenter" { type = string }
variable "cluster"    { type = string }
variable "datastore"  { type = string }
variable "network"    { type = string }

# --- Template ---
variable "template_name" { type = string; default = "VMhaproxy" }

# --- SSH (muss zum authorized-key in user-data passen) ---
variable "ssh_private_key_file" { type = string; default = "~/.ssh/id_ed25519" }

source "vsphere-iso" "haproxy" {
  vcenter_server      = var.vcenter_server
  username            = var.vcenter_user
  password            = var.vcenter_password
  insecure_connection = true

  datacenter = var.datacenter
  cluster    = var.cluster
  datastore  = var.datastore

  vm_name       = var.template_name
  guest_os_type = "ubuntu64Guest"
  CPUs          = 2
  RAM           = 2048

  disk_controller_type = ["pvscsi"]
  storage {
    disk_size             = 20480
    disk_thin_provisioned = true
  }

  network_adapters {
    network      = var.network
    network_card = "vmxnet3"
  }

  # Ubuntu 24.04 LTS
  iso_url      = "https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"
  iso_checksum = "sha256:d6fea1f6a97a2f34bfe8cc5a1b3c2bd8a24ef3b39adf97e7d2e48a3b2b461a38"

  # Cloud-init Autoinstall — haproxy + keepalived werden via user-data installiert
  cd_content = {
    "meta-data" = "instance-id: packer-build\n"
    "user-data" = file("${path.root}/user-data")
  }
  cd_label = "cidata"

  boot_order   = "disk,cdrom"
  boot_command = [
    "<esc><wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud <enter><wait>",
    "initrd /casper/initrd <enter><wait>",
    "boot <enter>"
  ]
  boot_wait = "5s"

  ssh_username         = "ubuntu"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "30m"

  shutdown_command = "echo 'ubuntu' | sudo -S shutdown -P now"

  content_library_destination {
    library = "Packer-Templates"
    name    = var.template_name
    ovf     = true
    destroy = true
  }
}

build {
  sources = ["source.vsphere-iso.haproxy"]

  # haproxy + keepalived bereits via cloud-init installiert
  # nur cleanup ausfuehren
  provisioner "shell" {
    execute_command = "echo 'ubuntu' | sudo -S bash -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "${path.root}/../scripts/05-cleanup.sh",
    ]
  }
}
