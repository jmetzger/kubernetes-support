# Kubernetes Support & Best Practices

## Inhalt

### K8s Cluster Deployment auf vSphere

* [k8s-deploy/](k8s-deploy/) — Packer, OpenTofu, Ansible

### Analyse & Dokumentation

* [Code-Analyse: Übersicht](opentofu-k8s/01-code-analyse.md)
* [Was gut gemacht ist](opentofu-k8s/01a-was-gut-ist.md)
* [Was verbessert werden sollte](opentofu-k8s/01b-was-verbessert-werden-sollte.md)
* [Multi-Cluster Self-Service via GitLab Formular](opentofu-k8s/02-multi-cluster-selfservice.md)
* [Modul-Struktur: vsphere-vm (DRY-Refactoring)](opentofu-k8s/04-modul-struktur-vsphere-vm.md)
* [GitLab CI/CD Deployment mit OpenTofu](opentofu-k8s/05-gitlab-cicd-deployment.md)
* [ArgoCD Autopilot — GitOps vom ersten Tag](opentofu-k8s/03-argocd-autopilot.md)

### Ansible Vault + GitLab CI/CD

* [Komplettes Beispiel-Setup](ansible-vault-example/SETUP.md)

### Persistent Storage

* [HPE CSI Driver – iSCSI + Multipath auf Debian](kubernetes-csi/hpe-csi-iscsi-multipath.md)

### OpenBAO

* [IDP (Kubernetes) mit OpenBao](openbao/idp-kubernetes.md)
* [SSH Public Keys aus OpenBao provisionieren](openbao/ssh-public-keys.md)

### ArgoCD Autopilot

* [Problem: zu großer Annotation-Inhalt lösen](argocd/autopilot/zu-grosser-annotation-inhalt.md)
