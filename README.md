# Kubernetes Support & Best Practices

Automatisiertes Deployen von Kubernetes-Clustern mit Packer, OpenTofu und Ansible auf VMware vSphere.

## Repository-Struktur

```
packer/       ← VM Gold Images bauen
opentofu/     ← VMs provisionieren
ansible/      ← VMs konfigurieren
.gitlab-ci.yml
```

## Code

### Packer — Gold Images

| Verzeichnis | Image | Enthält |
|---|---|---|
| [packer/k8s/](packer/k8s/) | VMk8s | containerd, kubeadm, kubelet, kubectl |
| [packer/haproxy/](packer/haproxy/) | VMhaproxy | haproxy, keepalived |
| [packer/scripts/](packer/scripts/) | shared | Provisioner-Scripts für beide Images |

### OpenTofu — Cluster provisionieren

| Datei | Inhalt |
|---|---|
| [opentofu/main.tf](opentofu/main.tf) | Provider + Backend |
| [opentofu/control-plane.tf](opentofu/control-plane.tf) | Control Plane VMs |
| [opentofu/haproxy.tf](opentofu/haproxy.tf) | HAProxy VMs |
| [opentofu/workernode.tf](opentofu/workernode.tf) | Worker VMs |
| [opentofu/variables.tf](opentofu/variables.tf) | Alle Variablen |
| [opentofu/modules/vsphere-vm/](opentofu/modules/vsphere-vm/) | Gemeinsames VM-Modul |

### Ansible — Cluster konfigurieren

| Verzeichnis | Inhalt |
|---|---|
| [ansible/haproxy-setup/](ansible/haproxy-setup/) | HAProxy + Keepalived installieren und finalisieren |
| [ansible/k8s-setup/](ansible/k8s-setup/) | Kubernetes initialisieren und Worker joinen |
| [ansible/inventory/](ansible/inventory/) | Ansible Inventory aus OpenTofu Outputs generieren |
| [ansible/teardown/](ansible/teardown/) | VMs loeschen |

## Dokumentation

### Analyse & Best Practices

* [Code-Analyse: Übersicht](opentofu-k8s/01-code-analyse.md)
* [Was gut gemacht ist](opentofu-k8s/01a-was-gut-ist.md)
* [Was verbessert werden sollte](opentofu-k8s/01b-was-verbessert-werden-sollte.md)

### Architektur & Design

* [Multi-Cluster Self-Service via GitLab Formular](opentofu-k8s/02-multi-cluster-selfservice.md)
* [Modul-Struktur: vsphere-vm (DRY-Refactoring)](opentofu-k8s/04-modul-struktur-vsphere-vm.md)
* [GitLab CI/CD Deployment mit OpenTofu](opentofu-k8s/05-gitlab-cicd-deployment.md)

### Weiteres

* [ArgoCD Autopilot — GitOps vom ersten Tag](opentofu-k8s/03-argocd-autopilot.md)
* [Ansible Vault + GitLab CI/CD Beispiel](ansible-vault-example/SETUP.md)

## Persistent Storage

* [HPE CSI Driver – iSCSI + Multipath auf Debian](kubernetes-csi/hpe-csi-iscsi-multipath.md)

## OpenBAO

* [IDP (Kubernetes) mit OpenBao](openbao/idp-kubernetes.md)
* [SSH Public Keys aus OpenBao provisionieren](openbao/ssh-public-keys.md)

## ArgoCD Autopilot

* [Problem: zu großer Annotation-Inhalt lösen](argocd/autopilot/zu-grosser-annotation-inhalt.md)
