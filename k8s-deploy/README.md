# K8s Cluster Deployment auf vSphere

Automatisiertes Deployen von Kubernetes-Clustern mit Packer, OpenTofu und Ansible auf VMware vSphere.

## Struktur

```
k8s-deploy/
  packer/       ← VM Gold Images bauen
  opentofu/     ← VMs provisionieren
  ansible/      ← VMs konfigurieren
```

## Packer — Gold Images

| Verzeichnis | Image | Enthält |
|---|---|---|
| [packer/k8s/](packer/k8s/) | VMk8s | containerd, kubeadm, kubelet, kubectl |
| [packer/haproxy/](packer/haproxy/) | VMhaproxy | haproxy, keepalived |
| [packer/scripts/](packer/scripts/) | shared | Provisioner-Scripts für beide Images |

## OpenTofu — Cluster provisionieren

| Datei | Inhalt |
|---|---|
| [opentofu/main.tf](opentofu/main.tf) | Provider + Backend |
| [opentofu/control-plane.tf](opentofu/control-plane.tf) | Control Plane VMs |
| [opentofu/haproxy.tf](opentofu/haproxy.tf) | HAProxy VMs |
| [opentofu/workernode.tf](opentofu/workernode.tf) | Worker VMs |
| [opentofu/variables.tf](opentofu/variables.tf) | Alle Variablen |
| [opentofu/modules/vsphere-vm/](opentofu/modules/vsphere-vm/) | Gemeinsames VM-Modul |

## Ansible — Cluster konfigurieren

| Verzeichnis | Inhalt |
|---|---|
| [ansible/haproxy-setup/](ansible/haproxy-setup/) | HAProxy + Keepalived installieren und finalisieren |
| [ansible/k8s-setup/](ansible/k8s-setup/) | Kubernetes initialisieren und Worker joinen |
| [ansible/inventory/](ansible/inventory/) | Ansible Inventory aus OpenTofu Outputs generieren |
| [ansible/teardown/](ansible/teardown/) | VMs loeschen |
