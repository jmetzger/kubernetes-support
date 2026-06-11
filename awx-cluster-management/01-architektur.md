# AWX + GitLab + OpenTofu: Cluster Management Konzept

## Ziel

Kubernetes-Cluster vollständig über AWX verwalten:
- Erstellen, skalieren, upgraden, löschen — alles via AWX Survey
- GitLab als einzige Source of Truth für Konfiguration und Zustand
- Keine manuellen Eingriffe in OpenTofu oder GitLab nötig

---

## Gesamtarchitektur

```
Operator
   │
   ▼
AWX Survey ausfüllen
   │
   ▼
Ansible Job (AWX Execution Node)
   ├── liest / schreibt  →  infra/clusters   (GitLab)
   └── führt aus         →  OpenTofu (tofu init / plan / apply)
                                │
                                ▼
                         Cloud Provider
                         (Cluster wird erstellt/geändert)
```

AWX ist die einzige Ausführungsebene. GitLab CI/CD wird **nicht** für OpenTofu verwendet.

---

## Die zwei Repositories

```
GitLab
├── infra/automation    ← Code: Ansible-Rollen + OpenTofu-Module
└── infra/clusters      ← Konfiguration: AWX schreibt hier
```

| | `infra/automation` | `infra/clusters` |
|---|---|---|
| Inhalt | Ansible-Rollen, OpenTofu-Module | tfvars, meta.yaml, versions.yaml, CHANGELOG |
| Wer schreibt | Menschen via MR + Review | AWX automatisch |
| Wer liest | AWX (Project Sync) | Ansible zur Laufzeit |
| Änderungsfrequenz | selten, bewusst | bei jedem Cluster-Event |
| AWX Project | ja (SCM Source) | nein |

### Warum zwei Repos?

AWX schreibt bei jeder Cluster-Operation in `infra/clusters` zurück.
Wäre das dasselbe Repo wie die Ansible-Rollen, würde AWX in seinen eigenen
Code-Stand schreiben — das vermischt Automation-Code mit Infrastruktur-Zustand
und macht den AWX Project Sync instabil.

---

## AWX Project Anbindung

```
infra/automation (GitLab)
        ↓  SCM Type: Git
AWX Project "K8s Cluster Management"
        ↓  referenziert Playbook-Datei
AWX Job Template "k8s-cluster-create"
        ↓  Survey + Credentials
Ansible Job auf AWX Execution Node
```

**AWX Project Einstellungen:**

| Feld | Wert |
|---|---|
| SCM Type | Git |
| SCM URL | `https://gitlab.example.com/infra/automation.git` |
| SCM Credential | GitLab Token |
| Branch | `main` |
| Update Revision on Launch | ✓ |

---

## AWX Job Templates

| Template | Zweck | Survey-Felder |
|---|---|---|
| `k8s-cluster-create` | Neuen Cluster erstellen | cluster_name, k8s_distro, worker_count, worker_flavor, cp_count, calico_version |
| `k8s-cluster-scale` | Worker skalieren | cluster_name, worker_count |
| `k8s-cluster-upgrade` | K8s-Version upgraden | cluster_name, target_version |
| `k8s-cluster-destroy` | Cluster löschen | cluster_name |

---

## AWX Credentials

Drei Credentials werden an den Job Templates hinterlegt:

```
Job Template
├── GitLab Token     → wird als {{ gitlab_token }} injiziert
│                      Rechte: infra/automation lesen,
│                              infra/clusters lesen + schreiben
├── Provider   → Env-Variablen (OS_AUTH_URL, OS_USERNAME, ...)
└── Survey           → cluster_name, k8s_version, ...
```

---

## Workflow: Cluster erstellen

```
1. AWX Survey ausfüllen
2. Ansible:
   a. infra/clusters klonen
   b. IPAM lesen → freie /24-Ranges zuweisen
   c. Ordner clusters/<name>/ anlegen
   d. meta.yaml, terraform.tfvars, versions.yaml, CHANGELOG.md schreiben
   e. IPAM aktualisieren
   f. Alles committen + pushen nach infra/clusters
3. OpenTofu:
   a. main.tf aus Template generieren (temporäres Verzeichnis)
   b. terraform.tfvars aus infra/clusters hineinkopieren
   c. tofu init / plan / apply
4. Temp-Verzeichnis bereinigen
```

## Workflow: Cluster skalieren

```
1. AWX Survey: cluster_name + worker_count
2. Ansible:
   a. infra/clusters klonen
   b. terraform.tfvars aktualisieren (nur worker_count)
   c. CHANGELOG.md: neuen Eintrag anhängen
   d. Committen + pushen
3. OpenTofu: tofu apply
```

## Workflow: K8s-Version upgraden

```
1. AWX Survey: cluster_name + target_version
2. Ansible Preflight:
   a. Aktuelle Version aus tfvars lesen
   b. Kein Downgrade?
   c. Kein Minor-Skip? (1.28 → 1.30 verboten)
3. Ansible:
   a. terraform.tfvars: kubernetes_version aktualisieren
   b. versions.yaml: k8s.version aktualisieren
   c. CHANGELOG.md: Upgrade-Eintrag anhängen
   d. Committen + pushen
4. OpenTofu: tofu apply (Control Plane zuerst, dann Worker)
```

## Workflow: Cluster löschen

```
1. AWX Survey: cluster_name
2. OpenTofu: tofu destroy
3. Ansible:
   a. IP-Ranges aus IPAM freigeben
   b. Cluster-Ordner archivieren oder löschen
   c. IPAM committen + pushen
```
