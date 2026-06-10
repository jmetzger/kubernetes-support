# K8s Cluster Deployment auf vSphere via GitLab CI/CD

Automatisiertes Deployen von Kubernetes-Clustern mit Packer, OpenTofu und Ansible auf VMware vSphere — orchestriert über GitLab CI/CD.

## Ablauf

```
GitLab CI/CD Pipeline
  │
  ├── 1. Packer    → Gold Images (VMk8s, VMhaproxy) in vSphere Content Library
  │
  ├── 2. OpenTofu  → VMs aus Gold Images klonen + Netzwerk konfigurieren
  │                  (HAProxy, Control Plane, Workernodes)
  │
  └── 3. Ansible   → Software konfigurieren
                     (HAProxy + Keepalived, kubeadm init, Worker joinen)
```

## GitLab CI/CD Pipeline

| Datei | Inhalt |
|---|---|
| [.gitlab-ci.yml](.gitlab-ci.yml) | Pipeline-Definition: Plan, Deploy, Destroy |

Die Pipeline wird manuell gestartet: **CI/CD → Pipelines → Run pipeline**. Dort alle Variablen (Cluster-Name, IP-Bereiche, Anzahl Nodes) ausfüllen und "Run pipeline" klicken.

## Struktur

```
k8s-deploy/
  .gitlab-ci.yml  ← Pipeline-Definition
  packer/         ← VM Gold Images bauen
  opentofu/       ← VMs provisionieren
  ansible/        ← VMs konfigurieren
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
