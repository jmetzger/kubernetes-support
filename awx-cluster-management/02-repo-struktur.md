# Repository-Struktur

## infra/automation

Enthält allen Code: Ansible-Rollen und OpenTofu-Module.
Wird von AWX als Project Source genutzt.

```
infra/automation/
├── playbooks/
│   ├── k8s-cluster-create.yml
│   ├── k8s-cluster-scale.yml
│   ├── k8s-cluster-upgrade.yml
│   └── k8s-cluster-destroy.yml
├── roles/
│   ├── k8s_cluster_create/
│   ├── k8s_cluster_scale/
│   ├── k8s_cluster_upgrade/
│   ├── k8s_cluster_destroy/
│   └── k8s_cluster_common/
│       └── tasks/
│           └── tofu_apply.yml      ← geteilt von allen Rollen
├── tofu-modules/
│   └── k8s-cluster/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── collections/
    └── requirements.yml
```

### Top-Level Playbook (Beispiel)

```yaml
# playbooks/k8s-cluster-create.yml
---
- name: Create Kubernetes Cluster
  hosts: localhost
  connection: local
  gather_facts: true
  roles:
    - k8s_cluster_create
```

`hosts: localhost` — OpenTofu läuft direkt auf dem AWX Execution Node.

---

## infra/clusters

Enthält ausschließlich Konfigurationsdaten. AWX schreibt hier bei jeder
Cluster-Operation automatisch rein.

```
infra/clusters/
├── _network/
│   └── ipam.yaml                   ← IP-Ranges: verfügbar + vergeben
│
├── prod-01/
│   ├── meta.yaml                   ← AWX-Herkunft, Modul-Version
│   ├── terraform.tfvars            ← Cluster-Variablen (OpenTofu)
│   ├── versions.yaml               ← Komponenten-Versionen
│   └── CHANGELOG.md                ← Änderungshistorie
│
├── dev-01/
│   ├── meta.yaml
│   ├── terraform.tfvars
│   ├── versions.yaml
│   └── CHANGELOG.md
│
└── staging-01/
    └── ...
```

---

## Dateibeschreibungen

### meta.yaml

Wird beim Erstellen von AWX geschrieben, danach nicht mehr verändert.
Dokumentiert Herkunft und genutzte Modul-Version.

```yaml
awx:
  template_id: 42
  template_name: "k8s-cluster-create"
  job_id: 1337
  launched_by: jmetzger
  created_at: "2026-06-11T10:00:00Z"
module_version: "v1.2.0"
survey_variables:
  cluster_name: prod-01
  k8s_distro: rke2
  k8s_version: "1.30"
  worker_count: 3
  worker_flavor: c3.large
  control_plane_count: 3
  calico_version: "3.27.0"
  containerd_version: "1.7.13"
```

### terraform.tfvars

Cluster-spezifische Variablen für OpenTofu. Wird bei scale und upgrade
von Ansible aktualisiert. Enthält auch die zugewiesenen IP-Ranges aus IPAM.

```hcl
cluster_name          = "prod-01"
kubernetes_version    = "1.30"
k8s_distro            = "rke2"
worker_count          = 3
worker_flavor         = "c3.large"
control_plane_count   = 3
calico_version        = "3.27.0"
containerd_version    = "1.7.13"

haproxy_subnet        = "10.10.1.0/24"
cp_subnet             = "10.10.2.0/24"
worker_subnet         = "10.10.3.0/24"
```

### versions.yaml

Aktueller Versionsstand aller Komponenten. Wird bei Upgrades aktualisiert.
Dient als schnelle Übersicht ohne tfvars lesen zu müssen.

```yaml
kubernetes:
  distribution: rke2
  version: "1.30.2"
calico:
  version: "3.27.0"
containerd:
  version: "1.7.13"
etcd:
  version: "3.5.10"
```

### CHANGELOG.md

Chronologische Änderungshistorie. Wird nie überschrieben, nur erweitert.

```markdown
# Cluster prod-01

## 2026-06-11 | Erstellt
- K8s: rke2 1.30.2
- Worker: 3 x c3.large
- Control Plane: 3 Nodes
- Calico: 3.27.0 / containerd: 1.7.13
- AWX Job: #1337 (k8s-cluster-create) — jmetzger

## 2026-07-01 | Scale-out
- Worker Nodes: 3 → 5
- AWX Job: #1402 (k8s-cluster-scale) — jmetzger

## 2026-08-15 | K8s Upgrade
- K8s Version: 1.30 → 1.31
- AWX Job: #1589 (k8s-cluster-upgrade) — mmustermann
```

---

## OpenTofu main.tf — kein fester Bestandteil von infra/clusters

Die `main.tf` wird von Ansible **zur Laufzeit generiert** und in einem
temporären Verzeichnis abgelegt. Sie wird nie nach `infra/clusters` committed.

Die Modul-Version steht in `meta.yaml` (Feld `module_version`) und wird
von Ansible beim Generieren der `main.tf` eingesetzt.

```hcl
# generiert durch Ansible aus templates/main.tf.j2
terraform {
  backend "http" {
    address        = "https://gitlab.example.com/api/v4/projects/PROJECT_ID/terraform/state/prod-01"
    lock_address   = ".../lock"
    unlock_address = ".../lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

module "cluster" {
  source = "git::https://gitlab.example.com/infra/automation.git//tofu-modules/k8s-cluster?ref=v1.2.0"
}
```

Der OpenTofu-State wird im **GitLab HTTP Backend** gespeichert —
direkt beim `infra/clusters` Projekt, kein separater State-Server nötig.
