# AWX Cluster Management — Code

Vollständiger Code für AWX-gesteuertes Kubernetes Cluster Management
mit GitLab als Source of Truth und OpenTofu für die Infrastruktur.

Konzept und Architektur: [../awx-cluster-management/](../awx-cluster-management/)

---

## Struktur

### infra-automation/ — Git Repo 1: Code

Wird als AWX Project eingebunden. Enthält Ansible-Rollen und das OpenTofu-Modul.

```
infra-automation/
├── playbooks/                        # Top-Level Playbooks (1 pro Job Template)
├── roles/
│   ├── k8s_cluster_common/           # Shared Tasks: tofu_apply, update_awx_survey
│   ├── k8s_cluster_create/           # Cluster erstellen
│   ├── k8s_cluster_scale/            # Worker skalieren
│   ├── k8s_cluster_upgrade/          # K8s-Version upgraden
│   └── k8s_cluster_destroy/          # Cluster löschen
├── tofu-modules/k8s-cluster/         # Geteiltes OpenTofu-Modul
└── collections/requirements.yml
```

### infra-clusters/ — Git Repo 2: Konfiguration

AWX schreibt hier automatisch nach jeder Cluster-Operation.
Enthält den aktuellen Zustand aller Cluster.

```
infra-clusters/
├── _network/ipam.yaml                # IP-Ranges: verfügbar + vergeben
├── _archived/                        # Gelöschte Cluster (nach destroy)
└── <cluster-name>/
    ├── meta.yaml                     # AWX-Herkunft, Modul-Version
    ├── terraform.tfvars              # Cluster-Variablen (OpenTofu)
    ├── versions.yaml                 # Aktuelle Komponenten-Versionen
    └── CHANGELOG.md                  # Änderungshistorie
```

### awx-setup/ — AWX Einrichtung

Einmalig beim Einrichten der AWX Job Templates ausführen.

```
awx-setup/
├── survey-specs/                     # JSON Survey-Specs für alle 4 Job Templates
└── init/awx-survey-init.yml          # Playbook: Survey-Specs initial befüllen
```

---

## AWX Job Templates

| Template | Playbook | Zweck |
|---|---|---|
| `k8s-cluster-create` | `playbooks/k8s-cluster-create.yml` | Neuen Cluster erstellen |
| `k8s-cluster-scale` | `playbooks/k8s-cluster-scale.yml` | Worker skalieren |
| `k8s-cluster-upgrade` | `playbooks/k8s-cluster-upgrade.yml` | K8s-Version upgraden |
| `k8s-cluster-destroy` | `playbooks/k8s-cluster-destroy.yml` | Cluster löschen |

## Anpassungen vor dem Einsatz

In allen `roles/*/defaults/main.yml` und `awx-setup/init/awx-survey-init.yml`:

| Variable | Beschreibung |
|---|---|
| `gitlab_url` | GitLab-URL |
| `gitlab_project_id` | Projekt-ID von `infra/clusters` |
| `awx_url` | AWX-URL |
| `awx_create_template_id` | Job Template ID von `k8s-cluster-create` |
| `clusters_repo` | Git-URL von `infra/clusters` |
