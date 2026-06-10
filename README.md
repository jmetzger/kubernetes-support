# Kubernetes Support & Best Practices

## Inhalt

### OpenTofu — K8s Cluster auf vSphere

Analyse, Best Practices und Verbesserungsvorschläge für das automatisierte Deployen von Kubernetes-Clustern mit OpenTofu + Ansible auf VMware vSphere.

* [Code-Analyse: Übersicht](opentofu-k8s/01-code-analyse.md)
* [Was gut gemacht ist — Best Practices mit Erklärungen](opentofu-k8s/01a-was-gut-ist.md)
* [Was verbessert werden sollte](opentofu-k8s/01b-was-verbessert-werden-sollte.md)
* [Multi-Cluster Self-Service via GitLab Formular](opentofu-k8s/02-multi-cluster-selfservice.md)
* [ArgoCD Autopilot — Übung: GitOps vom ersten Tag](opentofu-k8s/03-argocd-autopilot.md)
* [Modul-Struktur: vsphere-vm (DRY-Refactoring)](opentofu-k8s/04-modul-struktur-vsphere-vm.md)

### Ansible Vault + GitLab CI/CD

* [Komplettes Beispiel-Setup: Ansible Vault mit GitLab CI/CD](ansible-vault-example/SETUP.md)

### Persistent Storage

* [HPE CSI Driver – iSCSI + Multipath auf Debian](kubernetes-csi/hpe-csi-iscsi-multipath.md)

### OpenBAO

* [IDP (Kubernetes) mit OpenBao](openbao/idp-kubernetes.md)
* [SSH Public Keys aus OpenBao provisionieren](openbao/ssh-public-keys.md)

### ArgoCD Autopilot

* [Problem: zu großer Annotation-Inhalt lösen](argocd/autopilot/zu-grosser-annotation-inhalt.md)
