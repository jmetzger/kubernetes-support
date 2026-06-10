# Multi-Cluster Self-Service via GitLab

## Problem heute

Neuen K8s-Cluster deployen bedeutet:
- AWX Job Template kopieren
- Variablen anpassen
- Inventory anlegen
- Dokumentation manuell schreiben
- Nächstes Mal wieder von vorne

## Ziel

```
Nutzer öffnet GitLab → füllt Formular aus → Cluster läuft → Doku ist fertig
```

---

## GitLab Pipeline Inputs (seit v16)

GitLab unterstützt Formulare direkt in Pipelines — kein externes Tool nötig:

```yaml
# .gitlab-ci.yml
workflow:
  inputs:
    cluster_name:
      description: "Name des Clusters (z.B. k8s-prod)"
      type: string
    k8s_version:
      description: "Kubernetes Version"
      type: select
      options: ["1.35", "1.36"]
      default: "1.35"
    control_planes:
      description: "Anzahl Control Planes (1 oder 3)"
      type: select
      options: ["1", "3"]
      default: "3"
    worker_count:
      description: "Anzahl Worker Nodes"
      type: number
      default: 3
    datastore:
      description: "vSphere Datastore"
      type: select
      options: ["datastore-01", "datastore-02"]
```

---

## Automatische Dokumentation — `clusters.yml`

Nach jedem erfolgreichen Deploy schreibt die Pipeline den neuen Cluster automatisch in eine zentrale YAML-Datei:

```yaml
# clusters.yml — Source of Truth
clusters:
  - name: k8s-prod
    k8s_version: "1.35"
    control_planes: 3
    workers: 5
    vip: "10.x.x.200"
    datastore: datastore-01
    created: "2026-06-10"
    created_by: jmetzger
    pipeline: "https://gitlab.intern/k8s/deploy/pipelines/1234"

  - name: k8s-staging
    k8s_version: "1.34"
    control_planes: 1
    workers: 2
    vip: "10.x.x.210"
    datastore: datastore-02
    created: "2026-05-01"
    created_by: mmustermann
    pipeline: "https://gitlab.intern/k8s/deploy/pipelines/987"
```

```yaml
# Letzter Task in der Deploy-Pipeline
- name: clusters.yml aktualisieren
  script:
    - |
      python3 << 'EOF'
      import yaml, os

      with open('clusters.yml', 'r') as f:
          data = yaml.safe_load(f) or {'clusters': []}

      data['clusters'].append({
          'name':           os.environ['CLUSTER_NAME'],
          'k8s_version':    os.environ['K8S_VERSION'],
          'control_planes': int(os.environ['CP_COUNT']),
          'workers':        int(os.environ['WORKER_COUNT']),
          'created_by':     os.environ['GITLAB_USER_LOGIN'],
          'pipeline':       os.environ['CI_PIPELINE_URL'],
      })

      with open('clusters.yml', 'w') as f:
          yaml.dump(data, f, default_flow_style=False)
      EOF
    - git add clusters.yml
    - git commit -m "cluster: add ${CLUSTER_NAME} [skip ci]"
    - git push
```

> **`[skip ci]`** im Commit verhindert eine neue Pipeline — sonst Endlosschleife.

---

## Automatisches Versions-Monitoring

Eine täglich laufende Pipeline prüft ob neue K8s-Versionen verfügbar sind:

```yaml
# .gitlab-ci.yml
version-check:
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"   # täglich
  script:
    - |
      # Aktuelle K8s Releases von GitHub API holen
      LATEST=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases \
        | python3 -c "
      import json, sys
      releases = json.load(sys.stdin)
      for r in releases:
          if not r['prerelease'] and r['tag_name'].startswith('v1.'):
              print(r['tag_name'])
              break
      ")

      # Mit clusters.yml vergleichen
      python3 check-versions.py --latest $LATEST --clusters clusters.yml
```

Bei veralteten Clustern: automatisch ein GitLab Issue öffnen:

```
Issue: "Update verfügbar: k8s-staging läuft 1.34, aktuell ist 1.36"
Labels: k8s-update, staging
Assigned: mmustermann
```

---

## Update-Pipeline

Separate Pipeline mit Cluster-Auswahl aus `clusters.yml`:

```yaml
workflow:
  inputs:
    cluster_name:
      description: "Welcher Cluster soll updated werden?"
      type: select
      options:
        # wird per scheduled pipeline aus clusters.yml befüllt
        - k8s-prod
        - k8s-staging
    target_version:
      description: "Ziel-Version"
      type: select
      options: ["1.35", "1.36"]
```

Rolling Update via `kubeadm upgrade`:
1. Control Plane 1 updaten, warten
2. Control Plane 2+3 updaten, je warten
3. Worker rolling update (einer nach dem anderen)
4. `clusters.yml` aktualisieren

---

## Gesamtbild

```
┌──────────────────────────────────────────────────────┐
│  GitLab — Self-Service Portal                        │
│                                                      │
│  [Deploy Pipeline]   [Update Pipeline]   [Delete]   │
│       │                    │                │        │
│  Formular mit         Cluster-Liste    Cluster-Liste │
│  Parametern           aus clusters.yml  + Bestätigung│
└──────┬───────────────────┬─────────────────┬─────────┘
       │                   │                 │
       ▼                   ▼                 ▼
  OpenTofu          kubeadm upgrade     tofu destroy
  + Ansible              (rolling)      + Ansible cleanup
       │
       ▼
  clusters.yml ← automatisch aktualisiert
  GitLab Issue  ← automatisch bei Update verfügbar
```

**Ergebnis:** Kein manuelles Kopieren in AWX, keine veraltete Dokumentation, keine vergessenen Updates.
