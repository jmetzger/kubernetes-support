# Kubernetes Support & Best Practices

Automatisiertes Deployen von Kubernetes-Clustern mit Packer, OpenTofu und Ansible auf VMware vSphere.

## Repository-Struktur

```
k8s-deploy/
  packer/       ← VM Gold Images bauen
  opentofu/     ← VMs provisionieren
  ansible/      ← VMs konfigurieren
```

## Code

### Packer — Gold Images

| Verzeichnis | Image | Enthält |
|---|---|---|
| [k8s-deploy/packer/k8s/](k8s-deploy/packer/k8s/) | VMk8s | containerd, kubeadm, kubelet, kubectl |
| [k8s-deploy/packer/haproxy/](k8s-deploy/packer/haproxy/) | VMhaproxy | haproxy, keepalived |
| [k8s-deploy/packer/scripts/](k8s-deploy/packer/scripts/) | shared | Provisioner-Scripts für beide Images |

### OpenTofu — Cluster provisionieren

| Datei | Inhalt |
|---|---|
| [k8s-deploy/opentofu/main.tf](k8s-deploy/opentofu/main.tf) | Provider + Backend |
| [k8s-deploy/opentofu/control-plane.tf](k8s-deploy/opentofu/control-plane.tf) | Control Plane VMs |
| [k8s-deploy/opentofu/haproxy.tf](k8s-deploy/opentofu/haproxy.tf) | HAProxy VMs |
| [k8s-deploy/opentofu/workernode.tf](k8s-deploy/opentofu/workernode.tf) | Worker VMs |
| [k8s-deploy/opentofu/variables.tf](k8s-deploy/opentofu/variables.tf) | Alle Variablen |
| [k8s-deploy/opentofu/modules/vsphere-vm/](k8s-deploy/opentofu/modules/vsphere-vm/) | Gemeinsames VM-Modul |

### Ansible — Cluster konfigurieren

| Verzeichnis | Inhalt |
|---|---|
| [k8s-deploy/ansible/haproxy-setup/](k8s-deploy/ansible/haproxy-setup/) | HAProxy + Keepalived installieren und finalisieren |
| [k8s-deploy/ansible/k8s-setup/](k8s-deploy/ansible/k8s-setup/) | Kubernetes initialisieren und Worker joinen |
| [k8s-deploy/ansible/inventory/](k8s-deploy/ansible/inventory/) | Ansible Inventory aus OpenTofu Outputs generieren |
| [k8s-deploy/ansible/teardown/](k8s-deploy/ansible/teardown/) | VMs loeschen |

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
