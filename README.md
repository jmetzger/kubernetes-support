# Kubernetes Support & Best Practices

## Inhalt

### K8s Cluster Deployment auf vSphere

Automatisiertes Deployen von Kubernetes-Clustern auf VMware vSphere via GitLab CI/CD.

* [k8s-deploy/](k8s-deploy/) — Packer, OpenTofu, Ansible

### Analyse & Dokumentation

* [Code-Analyse: Übersicht](opentofu-k8s/01-code-analyse.md)
* [Was gut gemacht ist](opentofu-k8s/01a-was-gut-ist.md)
* [Was verbessert werden sollte](opentofu-k8s/01b-was-verbessert-werden-sollte.md)
* [Was behoben werden muss](opentofu-k8s/01c-was-behoben-werden-muss.md)
* [Multi-Cluster Self-Service via GitLab Formular](opentofu-k8s/02-multi-cluster-selfservice.md)
* [Modul-Struktur: vsphere-vm (DRY-Refactoring)](opentofu-k8s/04-modul-struktur-vsphere-vm.md)
* [GitLab CI/CD Deployment mit OpenTofu](opentofu-k8s/05-gitlab-cicd-deployment.md)
* [ArgoCD Autopilot — GitOps vom ersten Tag](opentofu-k8s/03-argocd-autopilot.md)

### AWX + GitLab + OpenTofu: Cluster Management Code

Vollständiger Code getrennt nach Repos und AWX-Setup — direkt einsatzbereit.

* [awx-cluster-management-code/](awx-cluster-management-code/) — infra-automation, infra-clusters, awx-setup

### AWX + GitLab + OpenTofu: Cluster Management

Vollständig AWX-gesteuertes Kubernetes Cluster Management mit GitLab als
Source of Truth und OpenTofu für die Infrastruktur.

* [Architektur & Workflows](awx-cluster-management/01-architektur.md)
* [Repository-Struktur (infra/automation + infra/clusters)](awx-cluster-management/02-repo-struktur.md)
* [Ansible-Rollen (create, scale, upgrade, destroy)](awx-cluster-management/03-ansible-rollen.md)
* [Netzwerk & IPAM (/16 → /24 pro Cluster)](awx-cluster-management/04-netzwerk-ipam.md)
* [AWX Survey Management (IP-Ranges synchron halten)](awx-cluster-management/05-awx-survey-management.md)

### Ansible & AWX

* [Komplettes Beispiel-Setup (Ansible Vault + GitLab CI/CD)](ansible-vault-example/SETUP.md)
* [AWX Survey-Spec dynamisch aus GitLab befüllen (IPAM)](ansible/awx-ipam-survey.md)
* [Survey-Formulare in AWX](ansible/ansible-survey.md)

### Persistent Storage

* [HPE CSI Driver – iSCSI + Multipath auf Debian](kubernetes-csi/hpe-csi-iscsi-multipath.md)

### OpenBAO

* [IDP (Kubernetes) mit OpenBao](openbao/idp-kubernetes.md)
* [SSH Public Keys aus OpenBao provisionieren](openbao/ssh-public-keys.md)

### ArgoCD Autopilot

* [Problem: zu großer Annotation-Inhalt lösen](argocd/autopilot/zu-grosser-annotation-inhalt.md)
